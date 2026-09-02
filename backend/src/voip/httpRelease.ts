import http from "node:http";
import https from "node:https";
import type { IntercomDevice } from "../types";
import { logger } from "../logger";

export async function releaseDoorViaHttp(ic: IntercomDevice): Promise<void> {
  const spec = ic.intercom.httpRelease;
  const url = spec?.url?.trim();
  if (!spec || !url) throw new Error("intercom has no HTTP release URL");
  const method = (spec.method ?? "GET").toUpperCase() === "POST" ? "POST" : "GET";
  const insecure = spec.insecureTls !== false;
  logger.info({ id: ic.id, method, url: redactUrl(url) }, "intercom door release (HTTP)");
  await httpRequest(url, {
    method,
    headers: spec.headers,
    body: method === "POST" ? spec.body : undefined,
    insecureTls: insecure
  });
}

function redactUrl(url: string): string {
  try {
    const u = new URL(url);
    if (u.username || u.password) {
      u.username = u.username ? "…" : "";
      u.password = u.password ? "…" : "";
    }
    return u.toString();
  } catch {
    return url;
  }
}

function httpRequest(
  urlStr: string,
  opts: {
    method: string;
    headers?: Record<string, string>;
    body?: string;
    insecureTls: boolean;
  }
): Promise<void> {
  return new Promise((resolve, reject) => {
    let u: URL;
    try {
      u = new URL(urlStr);
    } catch {
      reject(new Error("ongeldige HTTP-URL voor deuropen"));
      return;
    }
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? https : http;
    const headers: Record<string, string> = { ...(opts.headers ?? {}) };
    const body = opts.body;
    if (body && !headers["Content-Type"] && !headers["content-type"]) {
      headers["Content-Type"] = "text/plain;charset=utf-8";
    }
    const req = lib.request(
      {
        protocol: u.protocol,
        hostname: u.hostname,
        port: u.port || (isHttps ? 443 : 80),
        path: `${u.pathname}${u.search}`,
        method: opts.method,
        headers,
        rejectUnauthorized: isHttps ? !opts.insecureTls : undefined
      },
      (res) => {
        res.resume();
        if ((res.statusCode ?? 500) >= 400) {
          reject(new Error(`HTTP deuropen ${res.statusCode}`));
          return;
        }
        resolve();
      }
    );
    req.on("error", reject);
    req.setTimeout(8000, () => {
      req.destroy();
      reject(new Error("HTTP deuropen timeout"));
    });
    if (body) req.write(body);
    req.end();
  });
}
