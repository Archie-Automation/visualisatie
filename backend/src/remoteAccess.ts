/**
 * Remote toegang via Archie Cloud (VPS): één plek voor alles wat de app en
 * go2rtc/Asterisk moeten weten om buitenshuis te werken.
 *
 * Env (gezet door docker/install.sh na enrollment, zie cloud/README.md):
 *   REMOTE_URL     https://<klant-id>.archiecloud.nl   (leeg = alleen LAN)
 *   SERVER_ID      stabiele id van deze installatie (app herkent de juiste NUC)
 *   TURN_HOST      turn.archiecloud.nl                  (leeg = geen TURN)
 *   TURN_SECRET    gedeeld geheim met coturn (use-auth-secret)
 *   TURN_TTL       geldigheid van tijdelijke TURN-credentials in s (3600)
 *   WG_ADDRESS     10.80.x.y  WireGuard-adres van deze NUC (voor ICE/local_net)
 *   GO2RTC_RELAY_CANDIDATE  host:port op de VPS die naar deze NUC:8555 forwardt
 */
import crypto from "node:crypto";
import os from "node:os";

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export interface IceBundle {
  iceServers: IceServer[];
  /** LAN-adres van de NUC; de app gebruikt dit alleen ter informatie. */
  lanHost: string | null;
  remoteUrl: string | null;
  serverId: string | null;
  /** Seconden dat de TURN-credentials geldig zijn (0 = geen TURN). */
  ttl: number;
}

const DEFAULT_STUN = "stun:stun.cloudflare.com:3478";

function env(name: string): string | null {
  const v = process.env[name]?.trim();
  return v && v.length > 0 ? v : null;
}

export function remoteUrl(): string | null {
  const v = env("REMOTE_URL");
  if (!v) return null;
  return v.replace(/\/+$/, "");
}

export function serverId(): string | null {
  return env("SERVER_ID");
}

export function wgAddress(): string | null {
  const v = env("WG_ADDRESS");
  if (!v) return null;
  return v.split("/")[0];
}

export function turnTtlSeconds(): number {
  const n = Number(env("TURN_TTL") ?? 3600);
  return Number.isFinite(n) && n > 60 ? Math.floor(n) : 3600;
}

/** Eerste niet-interne IPv4 met CIDR (bijv. 192.168.1.20/24). */
export function detectLanInterface(): { address: string; cidr: string } | null {
  const nets = os.networkInterfaces();
  for (const [name, ifaces] of Object.entries(nets)) {
    // WireGuard/Docker-interfaces overslaan: we willen het echte huis-LAN.
    if (/^(wg|docker|br-|veth|tailscale)/.test(name)) continue;
    for (const net of ifaces ?? []) {
      if (net.family === "IPv4" && !net.internal) {
        return { address: net.address, cidr: net.cidr ?? `${net.address}/32` };
      }
    }
  }
  return null;
}

/** Netwerk-CIDR (host-bits op 0) uit een adres/prefix, voor pjsip local_net. */
export function networkCidr(cidr: string): string {
  const [addr, prefixRaw] = cidr.split("/");
  const prefix = Number(prefixRaw ?? 32);
  const parts = addr.split(".").map((p) => Number(p));
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p))) return cidr;
  const ip = ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0;
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  const net = (ip & mask) >>> 0;
  return `${(net >>> 24) & 255}.${(net >>> 16) & 255}.${(net >>> 8) & 255}.${net & 255}/${prefix}`;
}

/** Subnetten die Asterisk als "lokaal" moet zien: huis-LAN + WireGuard-hub. */
export function localNets(): string[] {
  const out: string[] = [];
  const lan = detectLanInterface();
  if (lan) out.push(networkCidr(lan.cidr));
  if (wgAddress()) out.push("10.80.0.0/16");
  return out;
}

/**
 * TURN REST-credentials (coturn `use-auth-secret`): username = "<expiry>:<user>",
 * credential = base64(HMAC-SHA1(secret, username)).
 */
export function turnCredentials(
  user: string,
  ttlSeconds: number = turnTtlSeconds()
): { username: string; credential: string; expiresAt: number } | null {
  const secret = env("TURN_SECRET");
  const host = env("TURN_HOST");
  if (!secret || !host) return null;
  const expiresAt = Math.floor(Date.now() / 1000) + ttlSeconds;
  const safeUser = user.replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 32);
  const username = `${expiresAt}:${safeUser}`;
  const credential = crypto
    .createHmac("sha1", secret)
    .update(username)
    .digest("base64");
  return { username, credential, expiresAt };
}

export function turnUrls(): string[] {
  const host = env("TURN_HOST");
  if (!host) return [];
  const explicit = env("TURN_URLS");
  if (explicit) {
    return explicit
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
  }
  return [
    `turn:${host}:3478?transport=udp`,
    `turns:${host}:443?transport=tcp`
  ];
}

/** ICE-lijst voor één gebruiker. Thuis blijft host-candidate winnen; TURN is reserve. */
export function iceBundleFor(user: string): IceBundle {
  const servers: IceServer[] = [{ urls: DEFAULT_STUN }];
  const urls = turnUrls();
  const cred = urls.length > 0 ? turnCredentials(user) : null;
  if (cred && urls.length > 0) {
    servers.push({ urls, username: cred.username, credential: cred.credential });
  }
  return {
    iceServers: servers,
    lanHost: detectLanInterface()?.address ?? null,
    remoteUrl: remoteUrl(),
    serverId: serverId(),
    ttl: cred ? turnTtlSeconds() : 0
  };
}

/** Extra go2rtc-candidates buiten het LAN: WireGuard-adres en VPS-relay. */
export function extraGo2rtcCandidates(): string[] {
  const out: string[] = [];
  const wg = wgAddress();
  if (wg) out.push(`${wg}:8555`);
  const relay = env("GO2RTC_RELAY_CANDIDATE");
  if (relay) out.push(relay);
  return out;
}
