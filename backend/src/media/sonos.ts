// Thin wrapper around the `sonos` npm package. Keeps the upstream API
// contained to this file so the rest of the codebase can pretend media
// players have a unified shape (see `MediaState`).
//
// We treat every `SonosDevice` as a stand-alone zone coordinator: group /
// stereo-pair handling is intentionally out of scope for the first pass,
// because the interesting actions from the dashboard (play, pause, volume,
// favourite) always work even when the zone is grouped.

import { logger } from "../logger";
import type {
  MediaPreset,
  MediaSearchResult,
  MediaSearchSection,
  MediaState,
  MediaTransport,
  SonosDevice
} from "../types";

/** Max hits kept per result section before the UI gets noisy. */
const SONOS_SECTION_LIMIT = 20;

/* ------------------------------------------------------------------ *
 *  Type shim. The `sonos` package ships no typings — we only need a  *
 *  small slice of its surface.                                       *
 * ------------------------------------------------------------------ */

interface SonosApi {
  host: string;
  port: number;
  play(uri?: string | undefined): Promise<boolean>;
  pause(): Promise<boolean>;
  stop(): Promise<boolean>;
  next(): Promise<boolean>;
  previous(): Promise<boolean>;
  togglePlayback(): Promise<boolean>;
  getVolume(): Promise<number>;
  setVolume(vol: number): Promise<boolean>;
  getMuted(): Promise<boolean>;
  setMuted(muted: boolean): Promise<boolean>;
  currentTrack(): Promise<{
    title?: string;
    artist?: string;
    album?: string;
    albumArtURI?: string;
    albumArtURL?: string;
    position?: number;
    duration?: number;
    uri?: string;
  }>;
  getCurrentState(): Promise<string>;
  getFavorites(): Promise<{
    returned: string;
    total: string;
    items: Array<{
      title: string;
      uri: string;
      albumArtURI?: string;
    }>;
  }>;
  playFavorite(favoriteName: string): Promise<boolean>;
  /** Search the *local* music library / Sonos playlists (not streaming services). */
  searchMusicLibrary(
    searchType: string,
    searchTerm: string,
    options?: Record<string, unknown>
  ): Promise<{
    returned?: string;
    total?: string;
    items?: Array<{
      title?: string;
      uri?: string;
      albumArtURI?: string;
      artist?: string;
      album?: string;
    }>;
  } | null>;
  getZoneAttrs(): Promise<{ CurrentZoneName?: string }>;
  /** Returns a flat device description object (UDN is a top-level field). */
  deviceDescription(): Promise<Record<string, unknown>>;
  /** Join the group of another zone identified by its display name. */
  joinGroup(otherDeviceZoneName: string): Promise<boolean>;
  /** Leave the current group and become a standalone zone. */
  leaveGroup(): Promise<boolean>;
  /** Clear the playback queue. */
  flush(): Promise<boolean>;
  /** Set the Spotify region token used when generating service metadata. */
  setSpotifyRegion(region: string): void;
}

interface SonosConstructor {
  new (host: string, port?: number): SonosApi;
}

interface AsyncDiscovery {
  discover(opts?: { timeout?: number }): Promise<SonosApi>;
}

interface AsyncDiscoveryConstructor {
  new (): AsyncDiscovery;
}

// Single require; the module's shape matches the shim above.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const sonosLib: {
  Sonos: SonosConstructor;
  AsyncDeviceDiscovery: AsyncDiscoveryConstructor;
} = require("sonos");

// Spotify-on-Sonos service token region. EU = "2311", US = "3079".
// node-sonos defaults to US, which fails for EU accounts, so default to EU
// here and allow an override via env for other regions.
const SONOS_SPOTIFY_REGION =
  process.env.SONOS_SPOTIFY_REGION?.trim().toUpperCase() === "US" ? "3079" : "2311";

/** Construct a Sonos client with the correct Spotify region preset. */
function makeClient(host: string, port: number): SonosApi {
  const c = new sonosLib.Sonos(host, port);
  try {
    c.setSpotifyRegion(SONOS_SPOTIFY_REGION);
  } catch {
    /* older lib without the setter — non-fatal */
  }
  return c;
}

/** One-shot SOAP check — does not use MediaManager drivers. */
export async function probeSonos(
  host: string,
  port = 1400
): Promise<{
  ok: boolean;
  zoneName?: string;
  state?: string;
  error?: string;
}> {
  const h = host?.trim() ?? "";
  if (!h) {
    return { ok: false, error: "Geen IP/host opgegeven" };
  }
  const p = Number.isFinite(port) && port > 0 ? Math.trunc(port) : 1400;
  const client = new sonosLib.Sonos(h, p);
  try {
    const [attrs, stateRaw] = await Promise.all([
      client.getZoneAttrs(),
      client.getCurrentState()
    ]);
    return {
      ok: true,
      zoneName: attrs?.CurrentZoneName,
      state: typeof stateRaw === "string" ? stateRaw : String(stateRaw)
    };
  } catch (err) {
    return {
      ok: false,
      error: briefErr(err)
    };
  }
}

/* ------------------------------------------------------------------ *
 *  Driver                                                            *
 * ------------------------------------------------------------------ */

export class SonosDriver {
  readonly deviceId: string;
  readonly brand = "sonos" as const;

  private client: SonosApi | null = null;
  private readonly device: SonosDevice;
  private discovering: Promise<SonosApi | null> | null = null;

  constructor(device: SonosDevice) {
    this.device = device;
    this.deviceId = device.id;
    if (device.sonos.host) {
      this.client = makeClient(device.sonos.host, device.sonos.port ?? 1400);
    }
  }

  /** Best-effort discovery when only a `room` name was configured. */
  private async ensureClient(): Promise<SonosApi | null> {
    if (this.client) return this.client;
    if (!this.device.sonos.room) return null;
    if (this.discovering) return this.discovering;

    this.discovering = (async () => {
      try {
        const disc = new sonosLib.AsyncDeviceDiscovery();
        const found = await disc.discover({ timeout: 5000 });
        try {
          found.setSpotifyRegion(SONOS_SPOTIFY_REGION);
        } catch {
          /* non-fatal */
        }
        const attrs = await found
          .getZoneAttrs()
          .catch(() => ({}) as { CurrentZoneName?: string });
        if (
          this.device.sonos.room &&
          attrs.CurrentZoneName !== this.device.sonos.room
        ) {
          logger.warn(
            {
              want: this.device.sonos.room,
              got: attrs.CurrentZoneName,
              id: this.device.id
            },
            "sonos: discovered zone but name doesn't match – using anyway"
          );
        }
        this.client = found;
        return found;
      } catch (err) {
        logger.warn({ err, id: this.device.id }, "sonos discovery failed");
        return null;
      } finally {
        this.discovering = null;
      }
    })();
    return this.discovering;
  }

  async poll(): Promise<MediaState> {
    const base: MediaState = {
      deviceId: this.device.id,
      brand: "sonos",
      online: false,
      transport: "stopped"
    };
    const client = await this.ensureClient();
    if (!client) return base;
    try {
      // Probe with getCurrentState first; if *that* fails the device is
      // unreachable and we should report offline rather than synthesise a
      // fake "stopped" state.
      const state = await client.getCurrentState();
      type Track = Awaited<ReturnType<SonosApi["currentTrack"]>>;
      const emptyTrack: Track = {};
      const transport = mapTransport(state);
      const [track, volume, muted] = await Promise.all([
        client.currentTrack().catch(() => emptyTrack),
        client.getVolume().catch(() => undefined as number | undefined),
        client.getMuted().catch(() => undefined as boolean | undefined)
      ]);

      let title = track.title?.trim();
      let artist = track.artist?.trim();
      let album = track.album?.trim();
      const rawArt = track.albumArtURL ?? track.albumArtURI;
      const sonosBase = `http://${this.device.sonos.host}:${this.device.sonos.port ?? 1400}`;
      const rawAbsArt = rawArt
        ? rawArt.startsWith("http")
          ? rawArt
          : `${sonosBase}${rawArt.startsWith("/") ? "" : "/"}${rawArt}`
        : undefined;
      // Proxy all Sonos image URLs through the backend to avoid CORS in browsers.
      // Do not speculate /getaa — empty or hanging responses block preset-art
      // fallback in the client (albumArt wins over preset matching).
      let albumArt =
        transport === "stopped" || transport === "buffering" || !rawAbsArt
          ? undefined
          : proxyArt(rawAbsArt);

      if (transport === "stopped") {
        title = undefined;
        artist = undefined;
        album = undefined;
      } else if (transport === "buffering") {
        title = undefined;
        artist = undefined;
        album = undefined;
      } else if (isUnusableTrackTitle(title, track.uri)) {
        title = undefined;
        if (isUnusableTrackTitle(artist, track.uri)) artist = undefined;
      }

      // For ICY radio streams the title often contains "STATION - SHOW" format.
      // Extract the first segment as the station name for preset-art matching.
      const icyStation =
        !track.albumArtURL && title && title.includes(" - ")
          ? title.split(" - ")[0]?.trim()
          : undefined;

      return {
        ...base,
        online: true,
        transport,
        title,
        artist,
        album,
        albumArt,
        source: icyStation ?? sourceFromUri(track.uri),
        currentUri: track.uri,
        volume,
        muted,
        position: track.position,
        duration: track.duration,
        lastUpdate: new Date().toISOString()
      };
    } catch (err) {
      logger.debug(
        { err: briefErr(err), id: this.device.id },
        "sonos poll failed (offline?)"
      );
      return base;
    }
  }

  async listPresets(): Promise<MediaPreset[]> {
    const client = await this.ensureClient();
    if (!client) return [];
    try {
      const favs = await client.getFavorites();
      const base = `http://${this.device.sonos.host}:${this.device.sonos.port ?? 1400}`;
      const sonosBase2 = `http://${this.device.sonos.host}:${this.device.sonos.port ?? 1400}`;
      return favs.items
        .filter((f) => f.title && f.title.trim().length > 0)
        .map((f) => {
          const rawImg = f.albumArtURI;
          const absImg = rawImg
            ? rawImg.startsWith("http")
              ? rawImg
              : `${sonosBase2}${rawImg.startsWith("/") ? "" : "/"}${rawImg}`
            : undefined;
          return {
            id: f.title as string,
            name: f.title as string,
            image: absImg ? proxyArt(absImg) : undefined,
            uri: f.uri ?? undefined
          };
        });
    } catch (err) {
      logger.debug(
        { err: briefErr(err), id: this.device.id },
        "sonos favorites fetch failed"
      );
      return [];
    }
  }

  async play(): Promise<void> {
    const c = await this.requireClient();
    await c.play();
  }
  async pause(): Promise<void> {
    const c = await this.requireClient();
    await c.pause();
  }
  async stop(): Promise<void> {
    const c = await this.requireClient();
    await c.stop();
  }
  async next(): Promise<void> {
    const c = await this.requireClient();
    await c.next();
  }
  async previous(): Promise<void> {
    const c = await this.requireClient();
    await c.previous();
  }
  async setVolume(v: number): Promise<void> {
    const c = await this.requireClient();
    await c.setVolume(clamp(Math.round(v), 0, 100));
  }
  async setMuted(muted: boolean): Promise<void> {
    const c = await this.requireClient();
    await c.setMuted(muted);
  }
  async playPreset(id: string, uri?: string): Promise<void> {
    const c = await this.requireClient();
    if (uri) {
      // Play directly via URI — more reliable than name-based lookup.
      await c.play(uri);
    } else {
      // Fallback: name-based lookup in the Sonos favourites list.
      await c.playFavorite(id);
    }
  }

  /** Play any content URI returned by [search] (favourite / playlist / track). */
  async playRef(ref: string): Promise<void> {
    const c = await this.requireClient();
    await c.play(ref);
  }

  /** Play a Spotify URI locally through the Sonos Spotify service. Spotify
   *  blocks Sonos via its Connect Web API, so we feed the track straight to
   *  the speaker instead. Requires Spotify to be added once in the Sonos app
   *  (Instellingen > Diensten) with the same account. */
  async playSpotify(ref: string): Promise<void> {
    const c = await this.requireClient();
    // node-sonos understands track/album/playlist/artistTopTracks URIs.
    // A plain artist URI from search must be mapped to its top tracks.
    const uri = ref.startsWith("spotify:artist:")
      ? ref.replace("spotify:artist:", "spotify:artistTopTracks:")
      : ref;
    try {
      // Replace the queue with the new selection, then start it.
      await c.flush().catch(() => undefined);
      await c.play(uri);
    } catch (err) {
      logger.warn({ err, id: this.device.id, ref }, "sonos: Spotify lokaal afspelen mislukt");
      throw new Error(
        "Spotify afspelen op de Sonos is mislukt. Controleer of Spotify in de " +
          "Sonos-app als dienst is gekoppeld (Instellingen > Diensten) met hetzelfde account."
      );
    }
  }

  /** Search what the locally-reachable Sonos exposes: saved favourites
   *  (incl. streaming content the user saved), Sonos playlists and the
   *  local music library. The Sonos local API cannot search the full
   *  Spotify/Tidal catalogue — that lives behind those services' own APIs. */
  async search(term: string): Promise<MediaSearchSection[]> {
    const client = await this.ensureClient();
    if (!client) return [];
    const q = term.trim();
    if (!q) return [];
    const needle = q.toLowerCase();
    const base = `http://${this.device.sonos.host}:${this.device.sonos.port ?? 1400}`;
    const sections: MediaSearchSection[] = [];

    // 1. Favourites — already includes saved streaming playlists/stations.
    try {
      const favs = await client.getFavorites();
      const hits = (favs.items ?? [])
        .filter((f) => f.title && f.title.toLowerCase().includes(needle))
        .map((f) => buildResult("favorite", f.title, undefined, f.albumArtURI, f.uri, base))
        .filter((r): r is MediaSearchResult => r !== null);
      if (hits.length) {
        sections.push({ title: "Favorieten", results: hits.slice(0, SONOS_SECTION_LIMIT) });
      }
    } catch (err) {
      logger.debug({ err: briefErr(err), id: this.device.id }, "sonos favourites search failed");
    }

    // 2. Sonos playlists + local library (artists/albums/tracks).
    const libQueries: Array<[MediaSearchResult["kind"], string, string]> = [
      ["playlist", "sonos_playlists", "Playlists"],
      ["track", "tracks", "Nummers"],
      ["album", "albums", "Albums"],
      ["artist", "artists", "Artiesten"]
    ];
    for (const [kind, searchType, title] of libQueries) {
      try {
        const res = await client.searchMusicLibrary(searchType, q);
        const hits = (res?.items ?? [])
          .map((it) => buildResult(kind, it.title, it.artist ?? it.album, it.albumArtURI, it.uri, base))
          .filter((r): r is MediaSearchResult => r !== null);
        if (hits.length) {
          sections.push({ title, results: hits.slice(0, SONOS_SECTION_LIMIT) });
        }
      } catch (err) {
        logger.debug(
          { err: briefErr(err), id: this.device.id, searchType },
          "sonos library search failed (no shared library?)"
        );
      }
    }

    return sections;
  }

  /** Join the group of the coordinator zone at the given host. */
  async joinGroup(coordinatorHost: string, coordinatorPort = 1400): Promise<void> {
    const c = await this.requireClient();
    // Resolve the zone name from the coordinator (required by the sonos library).
    const coordinator = new sonosLib.Sonos(coordinatorHost, coordinatorPort);
    const attrs = await coordinator.getZoneAttrs();
    const zoneName = attrs?.CurrentZoneName;
    if (!zoneName) throw new Error(`Cannot resolve zone name for ${coordinatorHost}`);
    await c.joinGroup(zoneName);
  }

  /** Leave the current group and become a standalone zone. */
  async leaveGroup(): Promise<void> {
    const c = await this.requireClient();
    // The sonos library's leaveGroup() works for members.
    // For coordinators it may be a no-op; we call it anyway and catch errors.
    try {
      await c.leaveGroup();
    } catch {
      // If leaveGroup fails (e.g. zone is already standalone), ignore.
    }
  }

  private _uuid: string | null = null;

  /** Returns the Sonos UUID (e.g. "RINCON_ABC123...01400"), cached after first call. */
  async getUUID(): Promise<string | null> {
    if (this._uuid) return this._uuid;
    const c = await this.ensureClient();
    if (!c) return null;
    try {
      const desc = await c.deviceDescription();
      // The sonos library returns a flat object; UDN is a top-level string field.
      const udn = (desc?.UDN as string) ?? "";
      // UDN format: "uuid:RINCON_XXXX" — strip the "uuid:" prefix
      const uuid = udn.startsWith("uuid:") ? udn.slice(5) : udn;
      if (uuid) this._uuid = uuid;
      return uuid || null;
    } catch (e) {
      return null;
    }
  }

  get host(): string { return this.device.sonos.host ?? ""; }
  get port(): number { return this.device.sonos.port ?? 1400; }

  /** Name to match against the Spotify Connect device list. */
  get spotifyTargetName(): string {
    return (
      this.device.sonos.spotifyDeviceName?.trim() ||
      this.device.name?.trim() ||
      this.device.sonos.room?.trim() ||
      this.device.id
    );
  }

  /** Candidate names for matching this speaker in Spotify Connect, best first.
   *  The live zone name (e.g. "Kantoor") equals what Spotify shows, so it is
   *  tried first — no manual configuration needed. */
  async spotifyTargetCandidates(): Promise<string[]> {
    const candidates: string[] = [];
    // 1) Explicit override always wins, if set.
    const override = this.device.sonos.spotifyDeviceName?.trim();
    if (override) candidates.push(override);
    // 2) Live zone name straight from the speaker (authoritative).
    try {
      const c = await this.ensureClient();
      const attrs = await c?.getZoneAttrs();
      const live = attrs?.CurrentZoneName?.trim();
      if (live) candidates.push(live);
    } catch {
      /* offline / non-fatal — fall back to config below */
    }
    // 3) Configured fallbacks.
    const room = this.device.sonos.room?.trim();
    const name = this.device.name?.trim();
    if (room) candidates.push(room);
    if (name) candidates.push(name);
    // De-duplicate while keeping order.
    return [...new Set(candidates)];
  }

  private async requireClient(): Promise<SonosApi> {
    const c = await this.ensureClient();
    if (!c) throw new Error(`sonos offline: ${this.device.id}`);
    return c;
  }

  /** If this changes in house.json, [MediaManager.rebuild] must drop the driver. */
  sameConnectionAs(other: SonosDevice): boolean {
    const a = this.device.sonos;
    const b = other.sonos;
    return (
      (a.host ?? "") === (b.host ?? "") &&
      (a.port ?? 1400) === (b.port ?? 1400) &&
      (a.room ?? "") === (b.room ?? "")
    );
  }
}

function mapTransport(s: string): MediaTransport {
  const v = s.toLowerCase();
  if (v.includes("play")) return "playing";
  if (v.includes("pause")) return "paused";
  if (v.includes("transit") || v.includes("buffer")) return "buffering";
  return "stopped";
}

/** Hide raw stream URLs / Sonos internal fragment names from the UI. */
function isUnusableTrackTitle(text?: string, uri?: string): boolean {
  const t = text?.trim() ?? "";
  if (!t) return false;
  if (/\.(aac|mp3|m4a|flac|wav|opus)(\?|#|$)/i.test(t)) return true;
  if (/^[a-z][a-z0-9+.-]*:/i.test(t)) return true;
  if (/TLPSTR|SID=|\bsid=/i.test(t)) return true;
  if (t.includes("?") && t.length < 80 && /[=&]/.test(t)) return true;
  const u = uri?.trim() ?? "";
  if (u && t === u) return true;
  return false;
}

/** Normalize a Sonos item into a playable search result. Requires a URI. */
function buildResult(
  kind: MediaSearchResult["kind"],
  title: string | undefined,
  subtitle: string | undefined,
  rawImg: string | undefined,
  uri: string | undefined,
  base: string
): MediaSearchResult | null {
  const t = title?.trim();
  const ref = uri?.trim();
  if (!t || !ref) return null;
  const absImg = rawImg
    ? rawImg.startsWith("http")
      ? rawImg
      : `${base}${rawImg.startsWith("/") ? "" : "/"}${rawImg}`
    : undefined;
  const sub = subtitle?.trim();
  return {
    id: ref,
    kind,
    title: t,
    subtitle: sub && sub.length ? sub : undefined,
    image: absImg ? proxyArt(absImg) : undefined,
    playRef: ref
  };
}

function sourceFromUri(uri?: string): string | undefined {
  if (!uri) return undefined;
  if (uri.startsWith("x-sonos-spotify:") || uri.includes("spotify")) return "Spotify";
  if (uri.startsWith("x-rincon-mp3radio:") || uri.includes("radio")) return "Radio";
  if (uri.startsWith("x-sonosapi-stream")) return "Stream";
  if (uri.startsWith("x-file-cifs:")) return "Bibliotheek";
  if (uri.startsWith("x-rincon-queue:")) return "Wachtrij";
  return undefined;
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

/** Proxy all image URLs through our backend to avoid browser CORS issues.
 *  Sonos CDN domains (sali.sonos.radio, tunein CDN, etc.) often lack CORS headers,
 *  which blocks loading in Flutter Web (CanvasKit renderer). Proxying everything
 *  through the backend sidesteps this completely. */
function proxyArt(url: string): string {
  if (!url) return url;
  return `/api/media-art?u=${encodeURIComponent(preferLargeSonosArt(url))}`;
}

/** Sonos `/getaa` without `s=1` is a tiny thumbnail; request the large variant. */
function preferLargeSonosArt(url: string): string {
  try {
    const parsed = new URL(url);
    if (!/\/getaa$/i.test(parsed.pathname)) return url;
    parsed.searchParams.set("s", "1");
    return parsed.toString();
  } catch {
    return url;
  }
}

/** `sonos` hands us verbose axios errors; strip them down to a readable
 *  one-liner so the log stays usable. */
function briefErr(err: unknown): string {
  if (err && typeof err === "object" && "message" in err) {
    return String((err as { message: unknown }).message);
  }
  return String(err);
}
