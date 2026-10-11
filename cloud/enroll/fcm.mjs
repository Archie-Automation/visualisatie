// Firebase Cloud Messaging (HTTP v1) zonder dependencies.
// Service-account-JSON uit de Firebase-console (Projectinstellingen →
// Serviceaccounts → Nieuwe privésleutel) op FIREBASE_SERVICE_ACCOUNT.
import crypto from "node:crypto";
import fs from "node:fs";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

let account = null;
let accountErr = null;
function loadAccount() {
  if (account || accountErr) return account;
  const p = (process.env.FIREBASE_SERVICE_ACCOUNT || "").trim();
  if (!p) {
    accountErr = "FIREBASE_SERVICE_ACCOUNT niet gezet";
    return null;
  }
  try {
    const a = JSON.parse(fs.readFileSync(p, "utf8"));
    if (!a.client_email || !a.private_key || !a.project_id) throw new Error("velden ontbreken");
    account = a;
  } catch (e) {
    accountErr = `service-account onleesbaar: ${String(e?.message || e)}`;
  }
  return account;
}

export function fcmStatus() {
  const a = loadAccount();
  return a ? { ok: true, projectId: a.project_id } : { ok: false, error: accountErr };
}

/** Publieke clientconfig voor de app (staat ook in elke APK; geen geheim). */
export function clientConfig() {
  const raw = (process.env.FCM_CLIENT_CONFIG || "").trim();
  if (!raw) return null;
  try {
    const c = JSON.parse(raw);
    return c && c.apiKey && c.appId && c.projectId && c.messagingSenderId ? c : null;
  } catch {
    return null;
  }
}

const b64url = (buf) => Buffer.from(buf).toString("base64url");

let tokenCache = { value: "", exp: 0 };
async function accessToken() {
  const a = loadAccount();
  if (!a) throw new Error(accountErr);
  const now = Math.floor(Date.now() / 1000);
  if (tokenCache.value && tokenCache.exp - 60 > now) return tokenCache.value;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(
    JSON.stringify({ iss: a.client_email, scope: SCOPE, aud: a.token_uri || "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })
  );
  const sig = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${claims}`), a.private_key);
  const assertion = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch(a.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    signal: AbortSignal.timeout(10_000)
  });
  if (!res.ok) throw new Error(`oauth ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  tokenCache = { value: j.access_token, exp: now + Number(j.expires_in || 3600) };
  return tokenCache.value;
}

/**
 * Data-bericht met hoge prioriteit naar één token.
 * Geeft { ok } of { ok:false, invalid:true } (token weg) of { ok:false, error }.
 */
async function sendOne(bearer, projectId, target, data, ttl) {
  const message = {
    token: target.token,
    data,
    android: { priority: "high", ttl: `${ttl}s` },
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "background" },
      payload: { aps: { "content-available": 1 } }
    }
  };
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
    body: JSON.stringify({ message }),
    signal: AbortSignal.timeout(10_000)
  });
  if (res.ok) return { ok: true };
  let body = {};
  try {
    body = await res.json();
  } catch {}
  const code = body?.error?.details?.find((d) => d.errorCode)?.errorCode || body?.error?.status || String(res.status);
  const invalid = res.status === 404 || code === "UNREGISTERED" || code === "INVALID_ARGUMENT";
  return { ok: false, invalid, error: code };
}

/** @returns {{sent:number, failed:number, invalid:string[]}} */
export async function sendToTokens(targets, data, ttl = 30) {
  const a = loadAccount();
  if (!a) throw new Error(accountErr);
  const bearer = await accessToken();
  const out = { sent: 0, failed: 0, invalid: [] };
  const queue = [...targets];
  const worker = async () => {
    for (;;) {
      const t = queue.shift();
      if (!t) return;
      try {
        const r = await sendOne(bearer, a.project_id, t, data, ttl);
        if (r.ok) out.sent += 1;
        else {
          out.failed += 1;
          if (r.invalid) out.invalid.push(t.token);
        }
      } catch {
        out.failed += 1;
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(8, queue.length) }, worker));
  return out;
}
