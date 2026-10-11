// Registry + WireGuard + Caddy voor Archie Cloud. Geen dependencies.
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const env = {
  domain: process.env.DOMAIN || "archiecloud.nl",
  publicIp: process.env.PUBLIC_IP || "",
  turnSecret: process.env.TURN_SECRET || "",
  adminToken: process.env.ENROLL_ADMIN_TOKEN || "",
  wgSubnet: process.env.WG_SUBNET || "10.80.0.0/16",
  wgServerAddress: process.env.WG_SERVER_ADDRESS || "10.80.0.1",
  wgPort: Number(process.env.WG_PORT || 51820),
  wgInterface: process.env.WG_INTERFACE || "wg0",
  caddyAdmin: process.env.CADDY_ADMIN || "http://127.0.0.1:2019",
  caddyfile: process.env.CADDYFILE || "/caddy/Caddyfile",
  acmeEmail: process.env.ACME_EMAIL || "",
  dataDir: process.env.DATA_DIR || "/data",
  peersConf: "/etc/wireguard/peers.conf",
  // App Links / Universal Links: koppellink opent de native app.
  androidPackage: process.env.ANDROID_PACKAGE || "com.example.luxe_knx",
  androidCertSha256: (process.env.ANDROID_CERT_SHA256 || "").trim(),
  appleTeamId: (process.env.APPLE_TEAM_ID || "").trim(),
  iosBundleId: process.env.IOS_BUNDLE_ID || "com.example.luxeKnx"
};

const registryPath = () => path.join(env.dataDir, "registry.json");

export function loadRegistry() {
  try {
    const raw = fs.readFileSync(registryPath(), "utf8");
    const r = JSON.parse(raw);
    r.servers ??= {};
    r.installers ??= {};
    r.codes ??= {};
    r.nextServerHost ??= 2; // 10.80.0.2 ...
    r.nextInstallerHost ??= 2; // 10.80.255.2 ...
    return r;
  } catch {
    return { servers: {}, installers: {}, codes: {}, nextServerHost: 2, nextInstallerHost: 2 };
  }
}

export function saveRegistry(r) {
  fs.mkdirSync(env.dataDir, { recursive: true });
  const tmp = registryPath() + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(r, null, 2) + "\n");
  fs.renameSync(tmp, registryPath());
}

// ── Codes ──────────────────────────────────────────────────────────────────
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // geen 0/O/1/I/L

export function newCode(r, label, ttlMinutes = 10) {
  const bytes = crypto.randomBytes(8);
  let s = "";
  for (let i = 0; i < 8; i++) s += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  const code = `${s.slice(0, 4)}-${s.slice(4)}`;
  r.codes[code] = {
    label: label || "",
    createdAt: new Date().toISOString(),
    expiresAt: Date.now() + ttlMinutes * 60_000
  };
  return code;
}

export function consumeCode(r, code) {
  const key = String(code || "").trim().toUpperCase();
  const c = r.codes[key];
  if (!c) return null;
  delete r.codes[key];
  if (Date.now() > c.expiresAt) return null;
  return c;
}

export function pruneCodes(r) {
  const now = Date.now();
  for (const [k, v] of Object.entries(r.codes)) {
    if (now > v.expiresAt) delete r.codes[k];
  }
}

// ── Adressen ───────────────────────────────────────────────────────────────
function baseOctets() {
  const [net] = env.wgSubnet.split("/");
  const o = net.split(".").map(Number);
  return [o[0], o[1]];
}

export function allocServerAddress(r) {
  const [a, b] = baseOctets();
  // host 2..65022, sla .255.x over (installateurs) en .0/.255 per /24.
  for (;;) {
    const h = r.nextServerHost++;
    const c = (h >> 8) & 255;
    const d = h & 255;
    if (c >= 255) throw new Error("wg-subnet vol");
    if (d === 0 || d === 255) continue;
    if (c === 0 && d === 1) continue;
    return `${a}.${b}.${c}.${d}`;
  }
}

export function allocInstallerAddress(r) {
  const [a, b] = baseOctets();
  const d = r.nextInstallerHost++;
  if (d >= 255) throw new Error("installateurs-range vol");
  return `${a}.${b}.255.${d}`;
}

export function newServerId(r) {
  for (;;) {
    const id = crypto.randomBytes(4).toString("hex");
    if (!r.servers[id]) return id;
  }
}

// ── WireGuard ──────────────────────────────────────────────────────────────
export function wgGenKeyPair() {
  const priv = execFileSync("wg", ["genkey"]).toString().trim();
  const pub = execFileSync("wg", ["pubkey"], { input: priv }).toString().trim();
  return { privateKey: priv, publicKey: pub };
}

export function wgServerPublicKey() {
  try {
    return execFileSync("wg", ["show", env.wgInterface, "public-key"]).toString().trim();
  } catch {
    const pk = path.join("/etc/wireguard", "server.pub");
    return fs.existsSync(pk) ? fs.readFileSync(pk, "utf8").trim() : "";
  }
}

function validPubKey(k) {
  return typeof k === "string" && /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$/.test(k);
}

export function assertPubKey(k) {
  if (!validPubKey(k)) throw new Error("ongeldige WireGuard public key");
}

/** Schrijf alle actieve peers naar peers.conf en laad ze in de interface. */
export function syncWireGuard(r) {
  const lines = ["# Door enroll gegenereerd. Niet met de hand bewerken."];
  const add = (label, pub, ip) => {
    lines.push(`# ${label}`, "[Peer]", `PublicKey = ${pub}`, `AllowedIPs = ${ip}/32`, "");
  };
  for (const s of Object.values(r.servers)) {
    if (!s.revoked) add(`server ${s.id} ${s.label}`, s.publicKey, s.wgAddress);
  }
  for (const i of Object.values(r.installers)) {
    if (!i.revoked) add(`installer ${i.name}`, i.publicKey, i.wgAddress);
  }
  fs.mkdirSync(path.dirname(env.peersConf), { recursive: true });
  fs.writeFileSync(env.peersConf, lines.join("\n"), { mode: 0o600 });
  try {
    execFileSync("wg", ["addconf", env.wgInterface, env.peersConf]);
  } catch (e) {
    console.warn("wg addconf mislukt (draait wg0?):", String(e?.message || e));
  }
}

export function wgRemovePeer(pub) {
  try {
    execFileSync("wg", ["set", env.wgInterface, "peer", pub, "remove"]);
  } catch (e) {
    console.warn("wg peer remove mislukt:", String(e?.message || e));
  }
}

// ── Caddy ──────────────────────────────────────────────────────────────────
/** assetlinks.json / apple-app-site-association, of null als er niets ingesteld is. */
export function wellKnownFiles() {
  const files = {};
  if (env.androidCertSha256) {
    files["assetlinks.json"] = JSON.stringify([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: {
          namespace: "android_app",
          package_name: env.androidPackage,
          sha256_cert_fingerprints: env.androidCertSha256.split(",").map((s) => s.trim().toUpperCase()).filter(Boolean)
        }
      }
    ]);
  }
  if (env.appleTeamId) {
    files["apple-app-site-association"] = JSON.stringify({
      applinks: {
        details: [{ appIDs: [`${env.appleTeamId}.${env.iosBundleId}`], components: [{ "/": "/pair", "?": { code: "?*" } }] }]
      }
    });
  }
  return Object.keys(files).length ? files : null;
}

export function buildCaddyfile(r) {
  const out = [];
  out.push("{");
  if (env.acmeEmail) out.push(`\temail ${env.acmeEmail}`);
  out.push("\tadmin 0.0.0.0:2019");
  out.push("}");
  out.push("");
  // Zelfde .well-known op het hoofddomein (Android verifieert *.domein daar)
  // en op elk klantdomein (iOS haalt het per host op).
  const wk = wellKnownFiles();
  const importWk = () => {
    if (wk) out.push("\timport wellknown");
  };
  if (wk) {
    out.push("(wellknown) {");
    for (const [name, body] of Object.entries(wk)) {
      out.push(`\thandle /.well-known/${name} {`);
      out.push("\t\theader Content-Type application/json");
      out.push("\t\theader Cache-Control \"public, max-age=3600\"");
      out.push(`\t\trespond \`${body}\` 200`);
      out.push("\t}");
    }
    out.push("}");
    out.push("");
  }
  out.push(`https://${env.domain} {`);
  importWk();
  out.push("\trespond \"Archie Cloud\" 200");
  out.push("}");
  out.push("");
  out.push(`https://enroll.${env.domain} {`);
  out.push("\treverse_proxy host.docker.internal:8090");
  out.push("}");
  out.push("");
  for (const s of Object.values(r.servers)) {
    if (s.revoked) continue;
    out.push(`# ${s.label || s.id}`);
    out.push(`https://${s.id}.${env.domain} {`);
    importWk();
    out.push("\tencode zstd gzip");
    out.push(`\treverse_proxy ${s.wgAddress}:4000 {`);
    out.push("\t\ttransport http {");
    out.push("\t\t\tdial_timeout 5s");
    out.push("\t\t}");
    out.push("\t}");
    out.push("}");
    out.push("");
  }
  return out.join("\n");
}

export async function syncCaddy(r) {
  const text = buildCaddyfile(r);
  fs.mkdirSync(path.dirname(env.caddyfile), { recursive: true });
  fs.writeFileSync(env.caddyfile, text);
  try {
    const res = await fetch(`${env.caddyAdmin}/load`, {
      method: "POST",
      headers: { "content-type": "text/caddyfile" },
      body: text,
      signal: AbortSignal.timeout(10_000)
    });
    if (!res.ok) {
      console.warn("caddy reload faalde:", res.status, await res.text());
      return false;
    }
    return true;
  } catch (e) {
    console.warn("caddy admin niet bereikbaar:", String(e?.message || e));
    return false;
  }
}

// ── Enrollment ─────────────────────────────────────────────────────────────
export async function enrollServer(r, { code, publicKey, hostname }) {
  const c = consumeCode(r, code);
  if (!c) return { error: "code ongeldig of verlopen" };
  assertPubKey(publicKey);
  for (const s of Object.values(r.servers)) {
    if (s.publicKey === publicKey && !s.revoked) {
      return { error: "deze sleutel is al aangemeld" };
    }
  }
  const id = newServerId(r);
  const wgAddress = allocServerAddress(r);
  r.servers[id] = {
    id,
    label: c.label,
    hostname: String(hostname || "").slice(0, 64),
    publicKey,
    wgAddress,
    createdAt: new Date().toISOString(),
    revoked: false
  };
  saveRegistry(r);
  syncWireGuard(r);
  await syncCaddy(r);
  return {
    serverId: id,
    remoteUrl: `https://${id}.${env.domain}`,
    wg: {
      address: `${wgAddress}/32`,
      serverPublicKey: wgServerPublicKey(),
      endpoint: `${env.publicIp}:${env.wgPort}`,
      allowedIps: env.wgSubnet,
      persistentKeepalive: 25
    },
    turn: { host: `turn.${env.domain}`, secret: env.turnSecret }
  };
}

export async function revokeServer(r, id) {
  const s = r.servers[id];
  if (!s) return false;
  s.revoked = true;
  s.revokedAt = new Date().toISOString();
  saveRegistry(r);
  wgRemovePeer(s.publicKey);
  syncWireGuard(r);
  await syncCaddy(r);
  return true;
}

export function newInstaller(r, name) {
  const safe = String(name || "").trim().replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 32);
  if (!safe) throw new Error("naam ontbreekt");
  if (r.installers[safe] && !r.installers[safe].revoked) {
    throw new Error("installateur bestaat al");
  }
  const kp = wgGenKeyPair();
  const wgAddress = allocInstallerAddress(r);
  r.installers[safe] = {
    name: safe,
    publicKey: kp.publicKey,
    wgAddress,
    createdAt: new Date().toISOString(),
    revoked: false
  };
  saveRegistry(r);
  syncWireGuard(r);
  const conf = [
    "[Interface]",
    `PrivateKey = ${kp.privateKey}`,
    `Address = ${wgAddress}/32`,
    "",
    "[Peer]",
    `PublicKey = ${wgServerPublicKey()}`,
    `Endpoint = ${env.publicIp}:${env.wgPort}`,
    `AllowedIPs = ${env.wgSubnet}`,
    "PersistentKeepalive = 25",
    ""
  ].join("\n");
  return { name: safe, wgAddress, config: conf };
}
