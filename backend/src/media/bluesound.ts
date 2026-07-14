// Minimal BluOS driver. Bluesound devices speak a plain-HTTP, XML
// response protocol on port 11000 — no SDK needed, no library to pin.
// The XML payloads are small and shallow, so we extract fields with a
// handful of regexes instead of pulling in an XML parser.
//
// Reference: https://helpdesk.bluesound.com/discussions/viewtopic.php?t=2293

import { logger } from "../logger";
import type {
  BluesoundDevice,
  MediaPreset,
  MediaSearchResult,
  MediaSearchSection,
  MediaState,
  MediaTransport
} from "../types";

/** Cap how many linked services we expand + hits per service to stay snappy. */
const BLUOS_MAX_SERVICES = 6;
const BLUOS_SECTION_LIMIT = 20;

export class BluesoundDriver {
  readonly deviceId: string;
  readonly brand = "bluesound" as const;

  private readonly device: BluesoundDevice;
  private readonly base: string;

  constructor(device: BluesoundDevice) {
    this.device = device;
    this.deviceId = device.id;
    const port = device.bluesound.port ?? 11000;
    this.base = `http://${device.bluesound.host}:${port}`;
  }

  async poll(): Promise<MediaState> {
    const state: MediaState = {
      deviceId: this.device.id,
      brand: "bluesound",
      online: false,
      transport: "stopped"
    };

    try {
      const xml = await this.get("/Status");
      const volume = num(xml, "volume");
      const muted = num(xml, "mute") === 1;
      const rawState = text(xml, "state") ?? "stop";
      const transport = mapTransport(rawState);
      let title = text(xml, "name") ?? text(xml, "title1");
      let artist = text(xml, "artist") ?? text(xml, "title2");
      let album = text(xml, "album") ?? text(xml, "title3");
      if (transport === "stopped") {
        title = undefined;
        artist = undefined;
        album = undefined;
      } else if (transport === "buffering") {
        title = undefined;
        artist = undefined;
        album = undefined;
      }
      return {
        ...state,
        online: true,
        transport,
        title,
        artist,
        album,
        albumArt: resolveImage(this.base, text(xml, "image")),
        source: text(xml, "service") ?? text(xml, "inputId"),
        volume,
        muted,
        position: num(xml, "secs"),
        duration: num(xml, "totlen"),
        lastUpdate: new Date().toISOString()
      };
    } catch (err) {
      logger.debug({ err, id: this.device.id }, "bluesound poll failed");
      return state;
    }
  }

  async listPresets(): Promise<MediaPreset[]> {
    try {
      const xml = await this.get("/Presets");
      const matches = [...xml.matchAll(/<preset\b([^/]*?)\/>/g)];
      return matches.map((m) => {
        const attrs = m[1] ?? "";
        return {
          id: attr(attrs, "id") ?? "",
          name: attr(attrs, "name") ?? "Preset",
          image: resolveImage(this.base, attr(attrs, "image"))
        };
      }).filter((p) => p.id !== "");
    } catch (err) {
      logger.debug({ err, id: this.device.id }, "bluesound presets failed");
      return [];
    }
  }

  async play(): Promise<void> {
    await this.get("/Play");
  }
  async pause(): Promise<void> {
    // BluOS toggles on /Pause when state=play, otherwise is a no-op.
    await this.get("/Pause?toggle=1");
  }
  async stop(): Promise<void> {
    await this.get("/Stop");
  }
  async next(): Promise<void> {
    await this.get("/Skip");
  }
  async previous(): Promise<void> {
    await this.get("/Back");
  }
  async setVolume(v: number): Promise<void> {
    const level = Math.max(0, Math.min(100, Math.round(v)));
    await this.get(`/Volume?level=${level}`);
  }
  async setMuted(muted: boolean): Promise<void> {
    await this.get(`/Volume?mute=${muted ? 1 : 0}`);
  }
  async playPreset(id: string, _uri?: string): Promise<void> {
    await this.get(`/Preset?id=${encodeURIComponent(id)}`);
  }

  /** Play a BluOS playURL (or preset path) returned by [search]. The playURL
   *  is a directly-invokable path such as "/Play?url=...". */
  async playRef(ref: string): Promise<void> {
    const r = ref.trim();
    if (!r) return;
    if (/^https?:\/\//i.test(r)) {
      // Absolute playURL — invoke directly without the device base prefix.
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 4000);
      try {
        await fetch(r, { signal: ctl.signal });
      } finally {
        clearTimeout(timer);
      }
      return;
    }
    await this.get(r.startsWith("/") ? r : `/${r}`);
  }

  /** Search the services the customer linked in the BluOS app. BluOS exposes
   *  these locally: we discover services via /Browse, read each service's
   *  searchKey, then run /Browse?key=<searchKey>&q=<term> per service. */
  async search(term: string): Promise<MediaSearchSection[]> {
    const q = term.trim();
    if (!q) return [];
    const needle = q.toLowerCase();
    const sections: MediaSearchSection[] = [];

    // 1. Presets matching the term — always available, no service round-trip.
    try {
      const presets = await this.listPresets();
      const hits = presets
        .filter((p) => p.name.toLowerCase().includes(needle))
        .map<MediaSearchResult>((p) => ({
          id: `preset:${p.id}`,
          kind: "favorite",
          title: p.name,
          image: p.image,
          playRef: `/Preset?id=${encodeURIComponent(p.id)}`
        }));
      if (hits.length) sections.push({ title: "Presets", results: hits });
    } catch (err) {
      logger.debug({ err, id: this.device.id }, "bluesound preset search failed");
    }

    // 2. Linked services discovered from the top-level browse.
    try {
      const top = await this.get("/Browse");
      const services = parseBrowseItems(top).filter((it) => it.browseKey && it.text);
      const picked = services.slice(0, BLUOS_MAX_SERVICES);
      const perService = await Promise.all(
        picked.map((svc) => this.searchService(svc, q))
      );
      for (const sec of perService) {
        if (sec && sec.results.length) sections.push(sec);
      }
    } catch (err) {
      logger.debug({ err, id: this.device.id }, "bluesound service discovery failed");
    }

    return sections;
  }

  /** Browse into a service to find its searchKey, then run the search. */
  private async searchService(
    svc: BrowseItem,
    term: string
  ): Promise<MediaSearchSection | null> {
    try {
      const inner = await this.get(
        `/Browse?key=${encodeURIComponent(svc.browseKey ?? "")}`
      );
      const searchKey = attr(inner, "searchKey");
      if (!searchKey) return null;
      const resXml = await this.get(
        `/Browse?key=${encodeURIComponent(searchKey)}&q=${encodeURIComponent(term)}`
      );
      const results = parseBrowseItems(resXml)
        .filter((it) => it.playURL && it.text)
        .slice(0, BLUOS_SECTION_LIMIT)
        .map<MediaSearchResult>((it) => ({
          id: it.playURL ?? "",
          kind: guessKind(it.type),
          title: it.text ?? "Onbekend",
          subtitle: it.text2,
          image: resolveImage(this.base, it.image),
          playRef: it.playURL ?? ""
        }));
      if (!results.length) return null;
      return { title: svc.text ?? "Service", results };
    } catch (err) {
      logger.debug(
        { err, id: this.device.id, service: svc.text },
        "bluesound service search failed"
      );
      return null;
    }
  }

  /** Add a slave player to this (master) device's group. */
  async addSlave(slaveHost: string, slavePort = 11000): Promise<void> {
    await this.get(`/AddSlave?host=${encodeURIComponent(slaveHost)}&port=${slavePort}`);
  }

  /** Remove a slave player from this (master) device's group. */
  async removeSlave(slaveHost: string, slavePort = 11000): Promise<void> {
    await this.get(`/RemoveSlave?host=${encodeURIComponent(slaveHost)}&port=${slavePort}`);
  }

  get host(): string { return this.device.bluesound.host; }
  get port(): number { return this.device.bluesound.port ?? 11000; }

  /** Name to match against the Spotify Connect device list. */
  get spotifyTargetName(): string {
    return (
      this.device.bluesound.spotifyDeviceName?.trim() ||
      this.device.name?.trim() ||
      this.device.id
    );
  }

  /** Candidate names for matching this player in Spotify Connect, best first.
   *  The live BluOS player name equals what Spotify shows, so it is tried
   *  first — no manual configuration needed. */
  async spotifyTargetCandidates(): Promise<string[]> {
    const candidates: string[] = [];
    const override = this.device.bluesound.spotifyDeviceName?.trim();
    if (override) candidates.push(override);
    // Live player name straight from BluOS (the SyncStatus "name" attribute).
    try {
      const xml = await this.get("/SyncStatus");
      const live = /<SyncStatus[^>]*\bname="([^"]+)"/i.exec(xml)?.[1]?.trim();
      if (live) candidates.push(live);
    } catch {
      /* offline / non-fatal — fall back to config below */
    }
    const name = this.device.name?.trim();
    if (name) candidates.push(name);
    return [...new Set(candidates)];
  }

  private async get(path: string): Promise<string> {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 4000);
    try {
      const res = await fetch(`${this.base}${path}`, { signal: ctl.signal });
      if (!res.ok) throw new Error(`bluesound ${path} → ${res.status}`);
      return await res.text();
    } finally {
      clearTimeout(timer);
    }
  }
}

/* ------------------------------ parsers ------------------------------ */

function text(xml: string, tag: string): string | undefined {
  // Non-greedy, allow attributes on opening tag. BluOS never escapes "<"
  // inside content, so a vanilla regex is safe for what we're parsing.
  const re = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, "i");
  const m = xml.match(re);
  if (!m || m[1] === undefined) return undefined;
  const val = m[1].trim();
  return val.length ? decodeEntities(val) : undefined;
}

function num(xml: string, tag: string): number | undefined {
  const v = text(xml, tag);
  if (v === undefined) return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

function attr(s: string, name: string): string | undefined {
  const m = s.match(new RegExp(`${name}="([^"]*)"`, "i"));
  if (!m) return undefined;
  return decodeEntities(m[1] ?? "");
}

function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

/** Subset of BluOS browse item attributes we care about. */
interface BrowseItem {
  text?: string;
  text2?: string;
  image?: string;
  playURL?: string;
  browseKey?: string;
  searchKey?: string;
  type?: string;
}

/** Extract every <item ...> opening tag's attributes from a BluOS response. */
function parseBrowseItems(xml: string): BrowseItem[] {
  const items: BrowseItem[] = [];
  const re = /<item\b([^>]*?)\/?>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const a = m[1] ?? "";
    items.push({
      text: attr(a, "text"),
      text2: attr(a, "text2"),
      image: attr(a, "image"),
      playURL: attr(a, "playURL"),
      browseKey: attr(a, "browseKey"),
      searchKey: attr(a, "searchKey"),
      type: attr(a, "type")
    });
  }
  return items;
}

function guessKind(type?: string): MediaSearchResult["kind"] {
  switch ((type ?? "").toLowerCase()) {
    case "album":
      return "album";
    case "artist":
      return "artist";
    case "playlist":
      return "playlist";
    case "radio":
      return "radio";
    case "song":
    case "track":
    case "audio":
      return "track";
    default:
      return "track";
  }
}

function mapTransport(s: string): MediaTransport {
  const v = s.toLowerCase();
  if (v === "play" || v === "stream") return "playing";
  if (v === "pause") return "paused";
  if (v === "connecting") return "buffering";
  return "stopped";
}

function resolveImage(base: string, image?: string): string | undefined {
  if (!image) return undefined;
  const abs = /^https?:\/\//i.test(image)
    ? image
    : `${base}${image.startsWith("/") ? "" : "/"}${image}`;
  // Proxy all image URLs through the backend to avoid browser CORS issues.
  return `/api/media-art?u=${encodeURIComponent(abs)}`;
}
