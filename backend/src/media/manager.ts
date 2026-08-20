// Owns every media driver (Sonos/Bluesound) and keeps a cached
// `MediaState` per device. A single interval polls all drivers so the
// UI sees "now playing" updates without having to hit the bus itself.
//
// Commands are routed here from `commands.ts`; state changes bubble up
// via the `onStateChanged` callback which the WS hub wires into its
// broadcast pipeline.

import { EventEmitter } from "node:events";
import { logger } from "../logger";
import type {
  Device,
  HouseConfig,
  MediaSearchSection,
  MediaState
} from "../types";
import { BluesoundDriver } from "./bluesound";
import { searchMediaDevice } from "./search";
import { SonosDriver } from "./sonos";
import * as spotify from "./spotify";
import { SpotifyAuthError } from "./spotify";

/** Polling cadence. Fast enough to feel live, slow enough not to
 *  hammer BluOS / Sonos gear running in a customer's rack. */
const POLL_INTERVAL_MS = 3000;
/** Refresh the (expensive) favourites/presets list less frequently. */
const PRESETS_INTERVAL_MS = 60_000;

type AnyDriver = SonosDriver | BluesoundDriver;

/** Artwork remembered for a specific content URI so radio/station
 *  switches don't keep the previous track's cover. */
type CachedArt = { uri: string; art: string };

export class MediaManager extends EventEmitter {
  private drivers = new Map<string, AnyDriver>();
  private states = new Map<string, MediaState>();
  private pollTimer: NodeJS.Timeout | null = null;
  private presetsTimer: NodeJS.Timeout | null = null;
  /** In-memory group map: memberId → coordinatorId */
  private groupMap = new Map<string, string>();
  /** Last-known artwork per device, keyed to the content URI it belonged to. */
  private lastPresetArt = new Map<string, CachedArt>();
  /** Sonos UUID → deviceId map, built lazily from device descriptions. */
  private sonosUuidToId = new Map<string, string>();
  /** Track which device IDs have already had their UUID fetched. */
  private sonosUuidFetched = new Set<string>();

  constructor() {
    super();
  }

  /** Replace the driver set based on the current config. Safe to call
   *  repeatedly — existing drivers for the same device id are kept so
   *  we don't thrash discovery. */
  rebuild(cfg: HouseConfig): void {
    const seen = new Set<string>();
    walk(cfg, (d) => {
      if (d.type === "media_sonos") {
        seen.add(d.id);
        const prev = this.drivers.get(d.id);
        if (prev instanceof SonosDriver && !prev.sameConnectionAs(d)) {
          this.drivers.delete(d.id);
          this.states.delete(d.id);
        }
        if (!this.drivers.has(d.id)) {
          this.drivers.set(d.id, new SonosDriver(d));
          this.states.set(d.id, baseState(d.id, "sonos"));
          logger.info({ id: d.id, name: d.name }, "media: Sonos driver ready");
        }
      } else if (d.type === "media_bluesound") {
        seen.add(d.id);
        if (!this.drivers.has(d.id)) {
          this.drivers.set(d.id, new BluesoundDriver(d));
          this.states.set(d.id, baseState(d.id, "bluesound"));
          logger.info({ id: d.id, name: d.name }, "media: Bluesound driver ready");
        }
      }
    });
    // Drop drivers for devices that were removed from the config.
    for (const id of [...this.drivers.keys()]) {
      if (!seen.has(id)) {
        this.drivers.delete(id);
        this.states.delete(id);
        logger.info({ id }, "media: driver removed");
      }
    }
  }

  start(): void {
    if (this.pollTimer) return;
    const tick = async () => {
      await Promise.all([...this.drivers.values()].map((drv) => this.pollOne(drv)));
      // After all zones are polled, auto-detect Sonos groups from currentUri.
      await this._syncSonosGroups().catch((e: unknown) =>
        logger.warn({ err: e }, "sonos group sync failed")
      );
    };
    // Fire once right away so the UI doesn't stare at an empty card.
    void tick();
    this.pollTimer = setInterval(tick, POLL_INTERVAL_MS);

    void this.refreshPresets();
    this.presetsTimer = setInterval(() => {
      void this.refreshPresets();
    }, PRESETS_INTERVAL_MS);
  }

  stop(): void {
    if (this.pollTimer) clearInterval(this.pollTimer);
    if (this.presetsTimer) clearInterval(this.presetsTimer);
    this.pollTimer = null;
    this.presetsTimer = null;
  }

  /* ------------------------------ API ----------------------------- */

  getAll(): MediaState[] {
    return [...this.states.values()];
  }

  get(id: string): MediaState | undefined {
    return this.states.get(id);
  }

  /** Search the services linked on a device, plus Spotify when connected.
   *  `needsSpotifyAuth` is true when a previously-connected Spotify account
   *  has become invalid, so the UI can prompt a reconnect. */
  async search(
    id: string,
    query: string
  ): Promise<{ sections: MediaSearchSection[]; needsSpotifyAuth: boolean }> {
    const drv = this.drivers.get(id);
    if (!drv) throw new Error(`unknown media device: ${id}`);
    const sections = await searchMediaDevice(drv, query);
    let needsSpotifyAuth = false;

    if (spotify.isConnected()) {
      try {
        const sp = await spotify.search(query);
        sections.push(...sp);
      } catch (err) {
        if (err instanceof SpotifyAuthError) {
          needsSpotifyAuth = true;
        } else {
          logger.warn({ err, id }, "spotify search failed");
        }
      }
    }
    return { sections, needsSpotifyAuth };
  }

  /** Play a search result on a device by its brand-specific reference.
   *  Spotify URIs are routed via Spotify Connect to the matching speaker. */
  async playItem(
    id: string,
    ref: string,
    meta?: { title?: string; image?: string }
  ): Promise<void> {
    const drv = this.drivers.get(id);
    if (!drv) throw new Error(`unknown media device: ${id}`);

    if (ref.startsWith("spotify:")) {
      if (drv instanceof SonosDriver) {
        // Spotify blocks Sonos via the Connect Web API, so play it locally
        // through the Sonos Spotify service instead.
        await drv.playSpotify(ref);
      } else {
        const candidates = await drv.spotifyTargetCandidates();
        await spotify.playOnDevice(candidates, ref);
      }
      if (meta?.image) this.lastPresetArt.set(id, { uri: ref, art: meta.image });
      setTimeout(() => void this.pollOne(drv), 1200);
      return;
    }

    // Cache the artwork so the tile doesn't go blank while the stream starts.
    if (meta?.image) this.lastPresetArt.set(id, { uri: ref, art: meta.image });
    await drv.playRef(ref);
    setTimeout(() => void this.pollOne(drv), 400);
  }

  /** Group `followerId` into the group of `coordinatorId`. */
  async group(followerId: string, coordinatorId: string): Promise<void> {
    if (followerId === coordinatorId) return;
    const follower = this.drivers.get(followerId);
    const coordinator = this.drivers.get(coordinatorId);
    if (!follower || !coordinator) throw new Error("unknown device(s) for grouping");

    // Update in-memory state first so the UI reflects intent immediately.
    this.groupMap.set(followerId, coordinatorId);
    // Clear the follower's cached art so the old artwork doesn't persist
    // after joining — _applyGroupFields will inject the coordinator's art.
    this.lastPresetArt.delete(followerId);
    this._applyGroupState();

    // Best-effort device API call — log on failure but don't undo the state.
    try {
      if (follower instanceof SonosDriver && coordinator instanceof SonosDriver) {
        await follower.joinGroup(coordinator.host, coordinator.port);
      } else if (follower instanceof BluesoundDriver && coordinator instanceof BluesoundDriver) {
        await coordinator.addSlave(follower.host, follower.port);
      } else {
        logger.warn({ followerId, coordinatorId }, "Cross-brand grouping skipped (UI-only)");
      }
    } catch (err) {
      logger.warn({ err, followerId, coordinatorId }, "Zone group API call failed (UI state kept)");
    }
    setTimeout(() => void this.pollOne(follower), 600);
    setTimeout(() => void this.pollOne(coordinator), 600);
  }

  /** Remove `deviceId` from its group.
   *
   * Handles both cases:
   *  - `deviceId` is a MEMBER   → remove it; coordinator stays with remaining members.
   *  - `deviceId` is a COORDINATOR → remove ALL its members too (whole group disbanded).
   */
  async ungroup(deviceId: string): Promise<void> {
    const drv = this.drivers.get(deviceId);
    if (!drv) throw new Error("unknown device");

    // Is this device a member of someone else's group?
    const myCoordId = this.groupMap.get(deviceId);

    // Is this device a coordinator — collect its current members.
    const myMembers: string[] = [];
    for (const [mId, cId] of this.groupMap) {
      if (cId === deviceId) myMembers.push(mId);
    }

    // ---------- Update in-memory groupMap ----------
    // Always remove this device as a member (if applicable).
    this.groupMap.delete(deviceId);
    // If this device is a coordinator, disband the whole group.
    for (const mId of myMembers) {
      this.groupMap.delete(mId);
    }
    this._applyGroupState();

    // ---------- Best-effort device API calls ----------
    try {
      if (drv instanceof SonosDriver) {
        // Always call leaveGroup on this device only.
        // • If it is a MEMBER: it detaches cleanly.
        // • If it is a COORDINATOR: Sonos hardware automatically promotes the
        //   first remaining member to coordinator — do NOT call leaveGroup on
        //   members, that would stop their playback unnecessarily.
        await drv.leaveGroup();
      } else if (drv instanceof BluesoundDriver) {
        if (myCoordId) {
          // Member leaving: tell coordinator to remove this slave.
          const coordDrv = this.drivers.get(myCoordId);
          if (coordDrv instanceof BluesoundDriver) {
            await coordDrv.removeSlave(drv.host, drv.port);
          }
        } else if (myMembers.length > 0) {
          // Coordinator leaving: remove all slaves from Bluesound perspective.
          for (const mId of myMembers) {
            const mDrv = this.drivers.get(mId);
            if (mDrv instanceof BluesoundDriver) {
              await drv.removeSlave(mDrv.host, mDrv.port).catch((e: unknown) =>
                logger.warn({ err: e, mId }, "removeSlave failed"));
            }
          }
        }
      }
    } catch (err) {
      logger.warn({ err, deviceId }, "Zone ungroup API call failed (UI state kept)");
    }

    // Re-poll all affected zones so the UI reflects the new state quickly.
    const allAffected = [drv, ...myMembers.flatMap(id => {
      const d = this.drivers.get(id); return d ? [d] : [];
    })];
    for (const d of allAffected) {
      setTimeout(() => void this.pollOne(d), 800);
    }
  }

  /** Auto-detect Sonos groups by inspecting each zone's currentUri.
   *  When a zone is a group member its URI is "x-rincon-stream:<coordinatorUUID>".
   *  This keeps groupMap in sync with hardware state after restarts. */
  private async _syncSonosGroups(): Promise<void> {
    // Build / refresh the UUID → deviceId map for Sonos drivers (once per device).
    for (const [id, drv] of this.drivers) {
      if (drv instanceof SonosDriver && !this.sonosUuidFetched.has(id)) {
        this.sonosUuidFetched.add(id); // mark as attempted even on failure
        const uuid = await drv.getUUID().catch((e: unknown) => {
          logger.warn({ err: e, id }, "sonos: UUID fetch failed");
          return null;
        });
        if (uuid) {
          this.sonosUuidToId.set(uuid, id);
          logger.info({ uuid, id }, "sonos: UUID mapped for group detection");
        } else {
          logger.warn({ id }, "sonos: could not determine UUID, group detection disabled for this device");
        }
      }
    }

    let changed = false;

    for (const [id, state] of this.states) {
      const uri = state.currentUri ?? "";
      // Sonos group member URIs: "x-rincon:<UUID>" or "x-rincon-stream:<UUID>"
      const memberMatch = uri.match(/^x-rincon(?:-stream)?:([^?]+)/i);
      if (memberMatch) {
        const coordUuid = memberMatch[1];
        const coordId = this.sonosUuidToId.get(coordUuid);
        if (coordId && coordId !== id && this.groupMap.get(id) !== coordId) {
          this.groupMap.set(id, coordId);
          this.lastPresetArt.delete(id); // clear stale art for member
          changed = true;
        }
      } else {
        // Zone is playing its own content — remove any stale member entry.
        if (this.groupMap.has(id)) {
          this.groupMap.delete(id);
          changed = true;
        }
      }
    }

    if (changed) {
      this._applyGroupState();
    }
  }

  private _applyGroupState(): void {
    // Collect coordinator → members mapping
    const coordMembers = new Map<string, string[]>();
    for (const [memberId, coordId] of this.groupMap) {
      const arr = coordMembers.get(coordId) ?? [];
      arr.push(memberId);
      coordMembers.set(coordId, arr);
    }
    for (const [id, state] of this.states) {
      const coordId = this.groupMap.get(id);
      const memberIds = coordMembers.get(id);
      let updated: MediaState;
      if (coordId) {
        updated = { ...state, groupRole: "member", groupCoordinatorId: coordId, groupMemberIds: undefined };
      } else if (memberIds && memberIds.length > 0) {
        updated = { ...state, groupRole: "coordinator", groupMemberIds: memberIds, groupCoordinatorId: undefined };
      } else {
        updated = { ...state, groupRole: "standalone", groupMemberIds: undefined, groupCoordinatorId: undefined };
      }
      // Also copy coordinator's now-playing info (including albumArt) to members.
      this._applyGroupFields(id, updated);
      this.states.set(id, updated);
      this.emit("stateChanged", updated);
    }
  }

  async command(
    id: string,
    cmd:
      | { action: "play" | "pause" | "stop" | "next" | "previous" }
      | { action: "volume"; value: number }
      | { action: "mute"; value: boolean }
      | { action: "preset"; presetId: string; uri?: string }
  ): Promise<void> {
    const drv = this.drivers.get(id);
    if (!drv) throw new Error(`unknown media device: ${id}`);

    switch (cmd.action) {
      case "play":
        await drv.play();
        break;
      case "pause":
        await drv.pause();
        break;
      case "stop":
        await drv.stop();
        break;
      case "next":
        await drv.next();
        break;
      case "previous":
        await drv.previous();
        break;
      case "volume":
        await drv.setVolume(cmd.value);
        break;
      case "mute":
        await drv.setMuted(cmd.value);
        break;
      case "preset": {
        // Store the preset's image so we can use it as albumArt fallback while
        // the device is playing (radio streams often carry no artwork of their own).
        const currentPresets = this.states.get(id)?.presets ?? [];
        const matchedPreset = currentPresets.find((p) => p.id === cmd.presetId);
        if (matchedPreset?.image) {
          this.lastPresetArt.set(id, {
            uri: matchedPreset.uri ?? cmd.uri ?? "",
            art: matchedPreset.image
          });
        }
        await drv.playPreset(cmd.presetId, cmd.uri);
        break;
      }
    }
    // Re-poll right away so the UI reflects the command without waiting
    // for the next periodic tick.
    setTimeout(() => void this.pollOne(drv), 400);
  }

  /* ---------------------------- internal -------------------------- */

  /** Fill / cache albumArt without carrying a previous track's cover onto
   *  a new radio station (or any other URI). */
  private _applyArtwork(
    id: string,
    prev: MediaState | undefined,
    next: MediaState
  ): void {
    if (next.transport === "stopped") {
      this.lastPresetArt.delete(id);
      next.albumArt = undefined;
      return;
    }

    const uri = next.currentUri ?? "";

    // Buffering still often reports the previous track's /getaa URL.
    if (next.transport === "buffering") {
      next.albumArt = undefined;
      const presetArt = matchPresetArt(next);
      if (presetArt) {
        next.albumArt = presetArt;
      } else {
        const cached = this.lastPresetArt.get(id);
        if (cached?.art) next.albumArt = cached.art;
      }
      return;
    }

    // Same art URL on a different URI is leftover from the previous source.
    if (
      next.albumArt &&
      prev?.currentUri &&
      uri !== prev.currentUri &&
      next.albumArt === prev.albumArt
    ) {
      next.albumArt = undefined;
    }

    if (next.albumArt) {
      this.lastPresetArt.set(id, { uri, art: next.albumArt });
      return;
    }

    const presetArt = matchPresetArt(next);
    if (presetArt) {
      next.albumArt = presetArt;
      this.lastPresetArt.set(id, { uri, art: presetArt });
      return;
    }

    const cached = this.lastPresetArt.get(id);
    if (cached?.art && cached.uri === uri) {
      next.albumArt = cached.art;
    } else {
      this.lastPresetArt.delete(id);
    }
  }

  private async pollOne(drv: AnyDriver): Promise<void> {
    try {
      const prev = this.states.get(drv.deviceId);
      const next = await drv.poll();
      // Preserve presets across polls — they change rarely.
      if (prev?.presets && !next.presets) next.presets = prev.presets;
      this._applyArtwork(drv.deviceId, prev, next);
      // Preserve group state — groupRole/members come from groupMap, not the device API.
      this._applyGroupFields(drv.deviceId, next);
      this.states.set(drv.deviceId, next);
      if (!shallowEqual(prev, next)) {
        this.emit("stateChanged", next);
      }
    } catch (err) {
      logger.warn({ err, id: drv.deviceId }, "media poll crashed");
    }
  }

  private async refreshPresets(): Promise<void> {
    for (const drv of this.drivers.values()) {
      try {
        const presets = await drv.listPresets();
        const cur = this.states.get(drv.deviceId);
        if (!cur) continue;
        const next: MediaState = { ...cur, presets };
        // Preserve group state in preset refreshes too.
        this._applyGroupFields(drv.deviceId, next);
        this.states.set(drv.deviceId, next);
        this.emit("stateChanged", next);
      } catch (err) {
        logger.debug({ err, id: drv.deviceId }, "presets refresh failed");
      }
    }
  }

  /** Stamp the current groupMap state onto a freshly-polled MediaState.
   *  For member zones, also copies the coordinator's "now playing" track info
   *  so the UI shows what the group is actually playing. */
  private _applyGroupFields(id: string, state: MediaState): void {
    const coordId = this.groupMap.get(id);
    if (coordId) {
      state.groupRole = "member";
      state.groupCoordinatorId = coordId;
      state.groupMemberIds = undefined;
      // For member zones, always use the coordinator's now-playing info.
      // Do NOT use "only if empty" — the member's own lastPresetArt cache
      // would otherwise keep the old artwork after grouping.
      const coordState = this.states.get(coordId);
      if (coordState && coordState.transport !== "stopped") {
        if (coordState.title) state.title = coordState.title;
        if (coordState.artist) state.artist = coordState.artist;
        if (coordState.album) state.album = coordState.album;
        if (coordState.albumArt) state.albumArt = coordState.albumArt;
        if (coordState.source) state.source = coordState.source;
        // NOTE: Do NOT copy currentUri from coordinator to member!
        // The member's raw currentUri (x-rincon:<UUID>) is what _syncSonosGroups
        // uses to detect group membership. Overwriting it would break auto-detection.
        // Sync transport so the tile shows "playing" on the member too.
        if ((state.transport as string) === "stopped") {
          state.transport = coordState.transport;
        }
      }
      return;
    }
    // Collect members whose coordinator is this device.
    const memberIds: string[] = [];
    for (const [memberId, cId] of this.groupMap) {
      if (cId === id) memberIds.push(memberId);
    }
    if (memberIds.length > 0) {
      state.groupRole = "coordinator";
      state.groupMemberIds = memberIds;
      state.groupCoordinatorId = undefined;
    } else {
      state.groupRole = "standalone";
      state.groupMemberIds = undefined;
      state.groupCoordinatorId = undefined;
    }
  }
}

/* ------------------------------ helpers ----------------------------- */

function walk(cfg: HouseConfig, fn: (d: Device) => void): void {
  for (const f of cfg.floors) for (const r of f.rooms) for (const d of r.devices) fn(d);
}

function baseState(id: string, brand: "sonos" | "bluesound"): MediaState {
  return { deviceId: id, brand, online: false, transport: "stopped" };
}

/** Match a preset logo when Sonos returns no artwork (common for AAC/ICY radio). */
function matchPresetArt(state: MediaState): string | undefined {
  const presets = state.presets;
  if (!presets?.length) return undefined;
  const uri = state.currentUri ?? "";

  for (const p of presets) {
    if (p.image && p.uri && p.uri === uri) return p.image;
  }
  if (state.source) {
    const sLower = state.source.toLowerCase();
    for (const p of presets) {
      if (p.image && p.name && sLower.includes(p.name.toLowerCase())) return p.image;
    }
  }
  if (state.title) {
    const tLower = state.title.toLowerCase().trim();
    for (const p of presets) {
      if (p.image && p.name && tLower === p.name.toLowerCase().trim()) {
        return p.image;
      }
    }
  }
  return undefined;
}

function shallowEqual(a: MediaState | undefined, b: MediaState): boolean {
  if (!a) return false;
  // Only compare fields the UI reacts to. `lastUpdate` is ignored so the
  // 3-second poll doesn't spam every client with a meaningless event.
  return (
    a.online === b.online &&
    a.transport === b.transport &&
    a.title === b.title &&
    a.artist === b.artist &&
    a.album === b.album &&
    a.albumArt === b.albumArt &&
    a.source === b.source &&
    a.currentUri === b.currentUri &&
    a.volume === b.volume &&
    a.muted === b.muted &&
    a.groupRole === b.groupRole &&
    a.groupCoordinatorId === b.groupCoordinatorId &&
    (a.groupMemberIds?.join(",") ?? "") === (b.groupMemberIds?.join(",") ?? "") &&
    presetsEqual(a.presets, b.presets)
  );
}

function presetsEqual(
  a?: MediaState["presets"],
  b?: MediaState["presets"]
): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i]?.id !== b[i]?.id || a[i]?.name !== b[i]?.name) return false;
  }
  return true;
}
