import type { MediaPreset, MediaState } from "../types";

export type MediaSkip =
  | { kind: "track" }
  | { kind: "preset"; preset: MediaPreset };

export function isRadioUri(uri?: string): boolean {
  if (!uri) return false;
  const u = uri.toLowerCase();
  if (u.includes("x-rincon-queue:")) return false;
  if (u.includes("spotify")) return false;
  if (u.startsWith("x-rincon-mp3radio:")) return true;
  if (u.includes("x-sonosapi-stream")) return true;
  if (u.includes("x-sonosapi-radio")) return true;
  if (u.includes("tunein")) return true;
  if (u.includes("sonos.radio")) return true;
  if (u.includes("mp3radio")) return true;
  if (u.includes("radio")) return true;
  return false;
}

export function isRadioSource(source?: string): boolean {
  if (!source) return false;
  const s = source.toLowerCase();
  if (s.includes("spotify") || s.includes("qobuz") || s.includes("tidal")) return false;
  return (
    s === "radio" ||
    s === "stream" ||
    s.includes("tunein") ||
    s.includes("radio") ||
    s.includes("airable") ||
    s.includes("iheart")
  );
}

export function isRadioPlayback(
  state: Pick<MediaState, "currentUri" | "source">,
  hintUri?: string
): boolean {
  if (isRadioUri(state.currentUri) || isRadioUri(hintUri)) return true;
  if (state.currentUri && !isRadioUri(state.currentUri)) {
    // Queue / Spotify / files win over a leftover "Radio" source label.
    const u = state.currentUri.toLowerCase();
    if (
      u.includes("x-rincon-queue:") ||
      u.includes("spotify") ||
      u.startsWith("x-file-cifs:")
    ) {
      return false;
    }
  }
  return isRadioSource(state.source);
}

function uriCore(uri: string): string {
  return uri.split("?")[0].toLowerCase().trim();
}

function nameKey(s: string): string {
  return s.toLowerCase().trim();
}

export function radioFavoriteRing(presets: MediaPreset[]): MediaPreset[] {
  if (presets.length === 0) return [];
  const withUri = presets.filter((p) => (p.uri ?? "").trim().length > 0);
  if (withUri.length === 0) return presets;
  return presets.filter((p) => isRadioUri(p.uri));
}

export function matchPresetIndex(
  state: Pick<MediaState, "currentUri" | "title" | "source">,
  presets: MediaPreset[],
  hintUri?: string
): number {
  if (presets.length === 0) return -1;
  const uri = (state.currentUri ?? "").trim();
  const hint = (hintUri ?? "").trim();

  if (uri) {
    const exact = presets.findIndex((p) => (p.uri ?? "") === uri);
    if (exact >= 0) return exact;
    const core = uriCore(uri);
    const byCore = presets.findIndex((p) => p.uri && uriCore(p.uri) === core);
    if (byCore >= 0) return byCore;
  }

  if (hint) {
    const byHint = presets.findIndex((p) => (p.uri ?? "") === hint);
    if (byHint >= 0) return byHint;
    const hintCore = uriCore(hint);
    const byHintCore = presets.findIndex((p) => p.uri && uriCore(p.uri) === hintCore);
    if (byHintCore >= 0) return byHintCore;
  }

  const source = nameKey(state.source ?? "");
  const title = nameKey(state.title ?? "");
  if (source) {
    const bySource = presets.findIndex((p) => {
      const n = nameKey(p.name);
      return n.length > 0 && source.includes(n);
    });
    if (bySource >= 0) return bySource;
  }
  if (title) {
    const byTitle = presets.findIndex((p) => {
      const n = nameKey(p.name);
      if (!n) return false;
      if (title === n) return true;
      return title.startsWith(`${n} - `) || title.startsWith(`${n}: `);
    });
    if (byTitle >= 0) return byTitle;
  }
  return -1;
}

export function resolveMediaSkip(
  state: MediaState | undefined,
  direction: 1 | -1,
  hintUri?: string
): MediaSkip {
  if (!state) return { kind: "track" };
  if (!isRadioPlayback(state, hintUri)) return { kind: "track" };
  const ring = radioFavoriteRing(state.presets ?? []);
  if (ring.length === 0) return { kind: "track" };
  const idx = matchPresetIndex(state, ring, hintUri);
  if (idx < 0) return { kind: "track" };
  const next = (idx + direction + ring.length) % ring.length;
  return { kind: "preset", preset: ring[next]! };
}
