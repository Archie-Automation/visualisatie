// Spotify integration via the Web API + Spotify Connect.
//
// - The installer sets SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET /
//   SPOTIFY_REDIRECT_URI on the server (env). The customer connects their own
//   Spotify account once via OAuth (Authorization Code flow).
// - Search returns normalized MediaSearchSection[] that slot into the same
//   player search sheet as the Sonos/Bluesound results.
// - Playback targets the speaker by its Spotify Connect device name, so a
//   selected track plays on exactly the player whose popup is open.

import { logger } from "../logger";
import fs from "node:fs";
import type { MediaSearchResult, MediaSearchSection } from "../types";
import {
  clearTokens,
  loadStore,
  saveCredentials,
  saveRedirectUri,
  saveTokens
} from "./spotifyStore";

const AUTH_BASE = "https://accounts.spotify.com";
const API_BASE = "https://api.spotify.com/v1";
const SCOPES = [
  "user-read-playback-state",
  "user-modify-playback-state",
  "user-read-private",
  "playlist-read-private"
].join(" ");

/** Thrown when Spotify is not connected / the token is no longer valid. */
export class SpotifyAuthError extends Error {
  constructor(message = "Spotify niet verbonden") {
    super(message);
    this.name = "SpotifyAuthError";
  }
}

// Credentials come from the in-app store first, then env vars as fallback.
function clientId(): string {
  return loadStore().clientId?.trim() || process.env.SPOTIFY_CLIENT_ID?.trim() || "";
}
function clientSecret(): string {
  return loadStore().clientSecret?.trim() || process.env.SPOTIFY_CLIENT_SECRET?.trim() || "";
}
function redirectUri(): string {
  return loadStore().redirectUri?.trim() || process.env.SPOTIFY_REDIRECT_URI?.trim() || "";
}

/** Spotify (2025) only allows https://… or http://127.0.0.1[:port] / http://[::1].
 *  LAN http (`http://192.168.x.x`) is rejected as "redirect_uri not matching". */
function isSpotifySafeRedirect(uri: string): boolean {
  try {
    const u = new URL(uri);
    if (u.protocol === "https:") return true;
    const host = u.hostname.toLowerCase();
    const loopback = host === "127.0.0.1" || host === "::1";
    return u.protocol === "http:" && loopback;
  } catch {
    return false;
  }
}

function lanHttpsCallback(serverBaseUrl?: string): string | undefined {
  const httpsPort = (process.env.HTTPS_PORT ?? "").trim();
  if (!httpsPort || httpsPort === "0") return undefined;
  const cert = process.env.TLS_CERT_PATH?.trim();
  if (cert && !fs.existsSync(cert)) return undefined;
  const base = (serverBaseUrl || process.env.PUBLIC_API_BASE || "").trim();
  if (!base) return undefined;
  try {
    const u = new URL(base.includes("://") ? base : `http://${base}`);
    const host = u.hostname;
    if (!host || host === "127.0.0.1" || host === "localhost" || host === "::1") {
      return undefined;
    }
    return `https://${host}:${httpsPort}/api/media/spotify/callback`;
  } catch {
    return undefined;
  }
}

function loopbackCallback(serverBaseUrl?: string): string {
  let port = "4000";
  const base = (serverBaseUrl || "").trim();
  if (base) {
    try {
      const u = new URL(base.includes("://") ? base : `http://${base}`);
      if (u.port) port = u.port;
    } catch {
      /* keep default */
    }
  }
  return `http://127.0.0.1:${port}/api/media/spotify/callback`;
}

function stripTrailingSlash(uri: string): string {
  return uri.replace(/\/+$/, "");
}

/** Configured = we have an app id + secret. The redirect URI can be derived
 *  from the server's own address when not explicitly set. */
export function isConfigured(): boolean {
  return !!(clientId() && clientSecret());
}

/** Save the OAuth app credentials entered in the app. Tokens from a previous
 *  app/account are dropped — they cannot be reused with a different client. */
export function saveAppCredentials(creds: {
  clientId?: string;
  clientSecret?: string;
  redirectUri?: string;
}): void {
  saveCredentials(creds);
  clearTokens();
}

/** Redirect URI that Spotify will accept. LAN http is not allowed; use the
 *  NUC HTTPS listener when present, otherwise loopback (same machine only). */
export function resolveRedirectUri(serverBaseUrl?: string): string {
  const env = process.env.SPOTIFY_REDIRECT_URI?.trim() || "";
  if (env && isSpotifySafeRedirect(env)) return stripTrailingSlash(env);
  const httpsCb = lanHttpsCallback(serverBaseUrl);
  if (httpsCb) return httpsCb;
  const derived = serverBaseUrl
    ? `${stripTrailingSlash(serverBaseUrl)}/api/media/spotify/callback`
    : "";
  if (derived && isSpotifySafeRedirect(derived)) return stripTrailingSlash(derived);
  return loopbackCallback(serverBaseUrl || derived);
}

export function isConnected(): boolean {
  return !!loadStore().refreshToken;
}

export function getStatus(): {
  configured: boolean;
  connected: boolean;
  account?: string;
  redirectUri?: string;
  /** Public OAuth client id, so the settings form can prefill when editing. */
  clientId?: string;
} {
  const store = loadStore();
  const storedRedirect = redirectUri();
  return {
    configured: isConfigured(),
    connected: !!store.refreshToken,
    account: store.displayName,
    redirectUri:
      storedRedirect && isSpotifySafeRedirect(storedRedirect)
        ? stripTrailingSlash(storedRedirect)
        : undefined,
    clientId: clientId() || undefined
  };
}

function basicAuthHeader(): string {
  const raw = `${clientId()}:${clientSecret()}`;
  return `Basic ${Buffer.from(raw).toString("base64")}`;
}

/** Build the Spotify authorize URL the customer is sent to. The resolved
 *  redirect URI is persisted so the callback's token exchange matches. */
export function buildAuthUrl(state: string, serverBaseUrl?: string): string {
  const redirect = resolveRedirectUri(serverBaseUrl);
  if (redirect) saveRedirectUri(redirect);
  logger.info({ redirect }, "spotify: authorize URL");
  const params = new URLSearchParams({
    response_type: "code",
    client_id: clientId(),
    scope: SCOPES,
    redirect_uri: redirect,
    state
  });
  return `${AUTH_BASE}/authorize?${params.toString()}`;
}

/** Exchange the authorization code for tokens + store them. */
export async function exchangeCode(code: string): Promise<void> {
  if (!isConfigured()) throw new Error("Spotify niet geconfigureerd");
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri()
  });
  const res = await fetch(`${AUTH_BASE}/api/token`, {
    method: "POST",
    headers: {
      authorization: basicAuthHeader(),
      "content-type": "application/x-www-form-urlencoded"
    },
    body
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`token exchange faalde (${res.status}): ${txt}`);
  }
  const json = (await res.json()) as {
    access_token: string;
    refresh_token?: string;
    expires_in: number;
  };
  let displayName: string | undefined;
  // Fetch the profile name for a friendly "verbonden als ..." label.
  try {
    const profile = await apiGet<{ display_name?: string }>("/me", json.access_token);
    displayName = profile.display_name;
  } catch {
    /* non-fatal */
  }
  saveTokens({
    refreshToken: json.refresh_token ?? "",
    accessToken: json.access_token,
    accessTokenExpiresAt: Date.now() + (json.expires_in - 60) * 1000,
    displayName
  });
  logger.info({ account: displayName }, "Spotify verbonden");
}

export function disconnect(): void {
  clearTokens();
  logger.info("Spotify ontkoppeld");
}

/** Returns a valid access token, refreshing if needed. */
async function getAccessToken(): Promise<string> {
  const tokens = loadStore();
  if (!tokens.refreshToken) throw new SpotifyAuthError();
  const now = Date.now();
  if (tokens.accessToken && tokens.accessTokenExpiresAt && tokens.accessTokenExpiresAt > now) {
    return tokens.accessToken;
  }
  // Refresh.
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: tokens.refreshToken
  });
  const res = await fetch(`${AUTH_BASE}/api/token`, {
    method: "POST",
    headers: {
      authorization: basicAuthHeader(),
      "content-type": "application/x-www-form-urlencoded"
    },
    body
  });
  if (res.status === 400 || res.status === 401) {
    // Refresh token revoked/invalid — force a reconnect.
    clearTokens();
    throw new SpotifyAuthError("Spotify-koppeling verlopen");
  }
  if (!res.ok) {
    throw new Error(`token refresh faalde (${res.status})`);
  }
  const json = (await res.json()) as {
    access_token: string;
    refresh_token?: string;
    expires_in: number;
  };
  const next = {
    refreshToken: json.refresh_token ?? tokens.refreshToken,
    accessToken: json.access_token,
    accessTokenExpiresAt: Date.now() + (json.expires_in - 60) * 1000,
    displayName: tokens.displayName
  };
  saveTokens(next);
  return next.accessToken!;
}

async function apiGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { authorization: `Bearer ${token}` }
  });
  if (res.status === 401) throw new SpotifyAuthError();
  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`Spotify GET ${path} faalde (${res.status}): ${txt}`);
  }
  return (await res.json()) as T;
}

/* -------------------------------- search -------------------------------- */

interface SpImage {
  url: string;
}
interface SpArtist {
  name: string;
}
interface SpTrack {
  uri: string;
  name: string;
  artists: SpArtist[];
  album?: { images?: SpImage[] };
}
interface SpAlbum {
  uri: string;
  name: string;
  artists: SpArtist[];
  images?: SpImage[];
}
interface SpArtistFull {
  uri: string;
  name: string;
  images?: SpImage[];
}
interface SpPlaylist {
  uri: string;
  name: string;
  owner?: { display_name?: string };
  images?: SpImage[];
}
interface SpSearchResponse {
  tracks?: { items: SpTrack[] };
  albums?: { items: SpAlbum[] };
  artists?: { items: SpArtistFull[] };
  playlists?: { items: SpPlaylist[] };
}

function proxyArt(url?: string): string | undefined {
  if (!url) return undefined;
  return `/api/media-art?u=${encodeURIComponent(url)}`;
}

/** Search the Spotify catalogue; returns sections ready for the player sheet. */
export async function search(query: string): Promise<MediaSearchSection[]> {
  const q = query.trim();
  if (!q) return [];
  const token = await getAccessToken();
  const params = new URLSearchParams({
    q,
    type: "track,album,artist,playlist",
    limit: "8"
  });
  const data = await apiGet<SpSearchResponse>(`/search?${params.toString()}`, token);

  const sections: MediaSearchSection[] = [];

  const tracks = (data.tracks?.items ?? [])
    .filter((t) => t && t.uri)
    .map<MediaSearchResult>((t) => ({
      id: t.uri,
      kind: "track",
      title: t.name,
      subtitle: t.artists.map((a) => a.name).join(", ") || undefined,
      image: proxyArt(t.album?.images?.[0]?.url),
      playRef: t.uri
    }));
  if (tracks.length) sections.push({ title: "Spotify - Nummers", results: tracks });

  const albums = (data.albums?.items ?? [])
    .filter((a) => a && a.uri)
    .map<MediaSearchResult>((a) => ({
      id: a.uri,
      kind: "album",
      title: a.name,
      subtitle: a.artists.map((x) => x.name).join(", ") || undefined,
      image: proxyArt(a.images?.[0]?.url),
      playRef: a.uri
    }));
  if (albums.length) sections.push({ title: "Spotify - Albums", results: albums });

  const artists = (data.artists?.items ?? [])
    .filter((a) => a && a.uri)
    .map<MediaSearchResult>((a) => ({
      id: a.uri,
      kind: "artist",
      title: a.name,
      subtitle: "Artiest",
      image: proxyArt(a.images?.[0]?.url),
      playRef: a.uri
    }));
  if (artists.length) sections.push({ title: "Spotify - Artiesten", results: artists });

  const playlists = (data.playlists?.items ?? [])
    .filter((p) => p && p.uri)
    .map<MediaSearchResult>((p) => ({
      id: p.uri,
      kind: "playlist",
      title: p.name,
      subtitle: p.owner?.display_name || undefined,
      image: proxyArt(p.images?.[0]?.url),
      playRef: p.uri
    }));
  if (playlists.length) sections.push({ title: "Spotify - Playlists", results: playlists });

  return sections;
}

/* ------------------------------- playback ------------------------------- */

interface SpDevice {
  id: string;
  name: string;
  is_active: boolean;
}

/** Play a Spotify URI on the Connect device matching one of [candidates].
 *  Candidates are tried in order (e.g. live room name first, config name as
 *  fallback) so the user never has to configure a name by hand. */
export async function playOnDevice(
  candidates: string | string[],
  uri: string
): Promise<void> {
  const names = (Array.isArray(candidates) ? candidates : [candidates])
    .map((n) => n?.trim())
    .filter((n): n is string => !!n);
  const token = await getAccessToken();
  const devices = (await apiGet<{ devices: SpDevice[] }>("/me/player/devices", token)).devices ?? [];
  const available = devices.map((d) => d.name);
  logger.info({ candidates: names, available }, "spotify: zoek Connect-apparaat");

  let target: SpDevice | undefined;
  for (const name of names) {
    target = findDevice(devices, name);
    if (target) break;
  }
  if (!target) {
    const list = available.length
      ? `Beschikbaar in Spotify Connect: ${available.map((n) => `"${n}"`).join(", ")}.`
      : `Er zijn op dit moment géén apparaten zichtbaar in Spotify Connect. ` +
        `Koppel je Spotify-account in de Sonos-app (Instellingen > Diensten) en ` +
        `speel er één keer iets op af, zodat de speaker in Spotify verschijnt.`;
    throw new Error(
      `Speler "${names[0] ?? ""}" is niet gevonden in Spotify Connect. ${list}`
    );
  }

  // Tracks play via `uris`; albums/playlists/artists via `context_uri`.
  const isTrack = uri.startsWith("spotify:track:");
  const playBody = isTrack ? { uris: [uri] } : { context_uri: uri };

  const res = await fetch(
    `${API_BASE}/me/player/play?device_id=${encodeURIComponent(target.id)}`,
    {
      method: "PUT",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json"
      },
      body: JSON.stringify(playBody)
    }
  );
  if (res.status === 401) throw new SpotifyAuthError();
  if (!res.ok && res.status !== 204) {
    const txt = await res.text().catch(() => "");
    throw new Error(`Spotify afspelen faalde (${res.status}): ${txt}`);
  }
}

function findDevice(devices: SpDevice[], name: string): SpDevice | undefined {
  const raw = name.trim().toLowerCase();
  if (!raw) return undefined;
  // Try the full name and a variant with a leading brand word stripped, since
  // a device configured as "Sonos Woonkamer" usually appears as just
  // "Woonkamer" in Spotify Connect.
  const stripped = raw.replace(/^(sonos|bluesound|bluos)\s+/i, "").trim();
  const needles = stripped && stripped !== raw ? [raw, stripped] : [raw];

  for (const needle of needles) {
    const hit =
      devices.find((d) => d.name.trim().toLowerCase() === needle) ??
      devices.find((d) => d.name.trim().toLowerCase().includes(needle)) ??
      devices.find((d) => needle.includes(d.name.trim().toLowerCase()));
    if (hit) return hit;
  }
  return undefined;
}
