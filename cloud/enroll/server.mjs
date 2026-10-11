// Enrollment-API voor Archie Cloud.
//   POST /enroll                 { code, publicKey, hostname }  (vanaf de NUC)
//   GET  /health
//   Admin (Authorization: Bearer ENROLL_ADMIN_TOKEN):
//   POST   /admin/codes          { label }           -> { code }
//   GET    /admin/servers
//   DELETE /admin/servers/:id
//   POST   /admin/installers     { name }            -> { config }
import http from "node:http";
import {
  enrollServer,
  env,
  loadRegistry,
  newCode,
  newInstaller,
  pruneCodes,
  revokeServer,
  saveRegistry,
  syncCaddy,
  syncWireGuard
} from "./lib.mjs";

const PORT = Number(process.env.PORT || 8090);

// Simpele brute-force-rem per IP voor /enroll.
const fails = new Map();
function tooMany(ip) {
  const now = Date.now();
  const e = fails.get(ip) || { n: 0, until: 0 };
  if (e.until > now) return true;
  return false;
}
function noteFail(ip) {
  const now = Date.now();
  const e = fails.get(ip) || { n: 0, until: 0, first: now };
  if (now - e.first > 60_000) {
    e.n = 0;
    e.first = now;
  }
  e.n += 1;
  if (e.n >= 5) e.until = now + 10 * 60_000;
  fails.set(ip, e);
}

function json(res, status, body) {
  const s = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(s),
    "cache-control": "no-store"
  });
  res.end(s);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 16_384) {
        reject(new Error("body te groot"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error("geen geldige JSON"));
      }
    });
    req.on("error", reject);
  });
}

function isAdmin(req) {
  const h = req.headers.authorization || "";
  return env.adminToken && h === `Bearer ${env.adminToken}`;
}

function clientIp(req) {
  const xf = req.headers["x-forwarded-for"];
  if (typeof xf === "string" && xf.length) return xf.split(",")[0].trim();
  return req.socket.remoteAddress || "?";
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", "http://x");
  const p = url.pathname;
  try {
    if (req.method === "GET" && p === "/health") {
      return json(res, 200, { ok: true, domain: env.domain });
    }

    if (req.method === "POST" && p === "/enroll") {
      const ip = clientIp(req);
      if (tooMany(ip)) return json(res, 429, { error: "te veel pogingen, wacht 10 minuten" });
      const body = await readBody(req);
      const r = loadRegistry();
      pruneCodes(r);
      let out;
      try {
        out = await enrollServer(r, body);
      } catch (e) {
        out = { error: String(e?.message || e) };
      }
      if (out.error) {
        noteFail(ip);
        saveRegistry(r);
        return json(res, 400, out);
      }
      console.log(`enroll ok ${out.serverId} (${body.hostname || "?"}) from ${ip}`);
      return json(res, 200, out);
    }

    if (p.startsWith("/admin/")) {
      if (!isAdmin(req)) return json(res, 401, { error: "unauthorized" });
      const r = loadRegistry();
      pruneCodes(r);

      if (req.method === "POST" && p === "/admin/codes") {
        const body = await readBody(req);
        const code = newCode(r, body.label, Number(body.ttlMinutes) || 10);
        saveRegistry(r);
        return json(res, 200, { code, expiresInMinutes: Number(body.ttlMinutes) || 10 });
      }
      if (req.method === "GET" && p === "/admin/servers") {
        const servers = Object.values(r.servers).map((s) => ({
          id: s.id,
          label: s.label,
          hostname: s.hostname,
          wgAddress: s.wgAddress,
          remoteUrl: `https://${s.id}.${env.domain}`,
          createdAt: s.createdAt,
          revoked: !!s.revoked
        }));
        const installers = Object.values(r.installers).map((i) => ({
          name: i.name,
          wgAddress: i.wgAddress,
          createdAt: i.createdAt,
          revoked: !!i.revoked
        }));
        const codes = Object.entries(r.codes).map(([code, c]) => ({
          code,
          label: c.label,
          expiresAt: new Date(c.expiresAt).toISOString()
        }));
        return json(res, 200, { servers, installers, codes });
      }
      const m = p.match(/^\/admin\/servers\/([a-f0-9]{8})$/);
      if (req.method === "DELETE" && m) {
        const ok = await revokeServer(r, m[1]);
        return json(res, ok ? 200 : 404, { ok });
      }
      if (req.method === "POST" && p === "/admin/installers") {
        const body = await readBody(req);
        const out = newInstaller(r, body.name);
        return json(res, 200, out);
      }
      if (req.method === "POST" && p === "/admin/sync") {
        syncWireGuard(r);
        const caddy = await syncCaddy(r);
        return json(res, 200, { ok: true, caddy });
      }
      return json(res, 404, { error: "not found" });
    }

    return json(res, 404, { error: "not found" });
  } catch (e) {
    console.error(e);
    return json(res, 500, { error: String(e?.message || e) });
  }
});

// Bij start: peers en Caddyfile in lijn brengen met de registry.
const r0 = loadRegistry();
syncWireGuard(r0);
syncCaddy(r0).then((ok) => {
  if (!ok) console.warn("Caddy nog niet herladen; probeer later /admin/sync");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`archie-cloud enroll op :${PORT} (${env.domain})`);
});
