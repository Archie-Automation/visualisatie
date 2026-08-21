// Persists the Spotify integration data for the household in one file
// (not house.json, so it never leaks to clients):
//   - credentials: client id/secret/redirect URI (entered once via the app)
//   - tokens: long-lived refresh token + cached access token
//
// Credentials and tokens are managed separately: disconnecting clears the
// tokens but keeps the credentials, so the customer can reconnect without
// re-entering keys.

import fs from "node:fs";
import path from "node:path";
import { logger } from "../logger";

export interface SpotifyStore {
  /** OAuth app credentials (optional — env vars are used as fallback). */
  clientId?: string;
  clientSecret?: string;
  redirectUri?: string;
  /** Tokens for the connected account. */
  refreshToken?: string;
  accessToken?: string;
  /** Epoch ms at which the access token expires. */
  accessTokenExpiresAt?: number;
  /** Spotify display name, for showing "verbonden als ...". */
  displayName?: string;
}

function storePath(): string {
  const fromEnv = process.env.SPOTIFY_STORE_PATH?.trim();
  if (fromEnv) return path.resolve(fromEnv);
  return path.join(process.cwd(), "data", "spotify.json");
}

// `undefined` = not loaded yet.
let cache: SpotifyStore | undefined;

export function loadStore(): SpotifyStore {
  if (cache !== undefined) return cache;
  const file = storePath();
  try {
    if (!fs.existsSync(file)) {
      cache = {};
      return cache;
    }
    const raw = JSON.parse(fs.readFileSync(file, "utf-8")) as SpotifyStore;
    cache = raw && typeof raw === "object" ? raw : {};
    return cache;
  } catch (err) {
    logger.warn({ err, file }, "spotify store kon niet worden geladen");
    cache = {};
    return cache;
  }
}

function write(next: SpotifyStore): void {
  const file = storePath();
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(next, null, 2), "utf-8");
    fs.renameSync(tmp, file);
    cache = next;
  } catch (err) {
    logger.warn({ err, file }, "spotify store opslaan mislukt");
  }
}

/** Merge OAuth app credentials (leaves tokens untouched — the caller
 *  decides whether to drop them, e.g. after a client-id change). */
export function saveCredentials(creds: {
  clientId?: string;
  clientSecret?: string;
  redirectUri?: string;
}): void {
  const cur = loadStore();
  write({
    ...cur,
    clientId: creds.clientId?.trim() || cur.clientId,
    clientSecret: creds.clientSecret?.trim() || cur.clientSecret,
    redirectUri: creds.redirectUri?.trim() || cur.redirectUri
  });
}

/** Persist the redirect URI actually used so the callback matches exactly. */
export function saveRedirectUri(redirectUri: string): void {
  const cur = loadStore();
  if (cur.redirectUri === redirectUri) return;
  write({ ...cur, redirectUri });
}

/** Merge account tokens (leaves credentials untouched). */
export function saveTokens(tokens: {
  refreshToken: string;
  accessToken?: string;
  accessTokenExpiresAt?: number;
  displayName?: string;
}): void {
  const cur = loadStore();
  write({
    ...cur,
    refreshToken: tokens.refreshToken,
    accessToken: tokens.accessToken,
    accessTokenExpiresAt: tokens.accessTokenExpiresAt,
    displayName: tokens.displayName
  });
}

/** Clear only the account tokens; credentials are kept. */
export function clearTokens(): void {
  const cur = loadStore();
  write({
    clientId: cur.clientId,
    clientSecret: cur.clientSecret,
    redirectUri: cur.redirectUri
  });
}
