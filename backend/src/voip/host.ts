/** Hostname/IP that SIP clients should use as registrar. */
export function parseVoipHost(raw: string | undefined | null): string | null {
  const t = (raw ?? "").trim();
  if (!t) return null;
  try {
    const u = new URL(t.includes("://") ? t : `http://${t}`);
    if (u.hostname) return u.hostname.replace(/^\[|\]$/g, "");
  } catch {
    /* ignore */
  }
  const stripped = t.replace(/^\[|\]$/g, "").replace(/:\d+$/, "");
  return stripped || null;
}

export function isLoopbackHost(host: string): boolean {
  const x = host.trim().toLowerCase();
  return x === "localhost" || x === "127.0.0.1" || x === "::1" || x === "[::1]";
}
