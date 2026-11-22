import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { dataDir, readServerUpdateStatus } from "./serverUpdate";

const execFileAsync = promisify(execFile);

export type HostNetworkMode = "dhcp" | "static";

export type HostNetworkView = {
  available: boolean;
  iface: string | null;
  mode: HostNetworkMode | null;
  address: string | null;
  prefix: number | null;
  gateway: string | null;
  dns: string[];
  pending: boolean;
  deadline: string | null;
  message: string | null;
};

type PendingFile = {
  since?: string;
  deadline?: string;
  applied?: boolean;
  mode?: HostNetworkMode;
  address?: string | null;
  previousAddress?: string | null;
};

const REQUEST = "network-request.json";
const PENDING = "network-pending.json";
const CONFIRM = "network-confirm.json";
const ERROR_FILE = "network-error.json";

function fileOf(name: string): string {
  return path.join(dataDir(), name);
}

function ipv4Parts(value: string): number[] | null {
  const parts = value.trim().split(".");
  if (parts.length !== 4) return null;
  const nums = parts.map((p) => Number(p));
  if (nums.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return null;
  return nums;
}

export function isIpv4(value: string): boolean {
  return ipv4Parts(value) !== null;
}

function ipv4ToInt(parts: number[]): number {
  return ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0;
}

function sameSubnet(a: string, b: string, prefix: number): boolean {
  const pa = ipv4Parts(a);
  const pb = ipv4Parts(b);
  if (!pa || !pb || prefix < 0 || prefix > 32) return false;
  if (prefix === 0) return true;
  const mask = prefix === 32 ? 0xffffffff : (0xffffffff << (32 - prefix)) >>> 0;
  return (ipv4ToInt(pa) & mask) === (ipv4ToInt(pb) & mask);
}

function unusableAddress(ip: string): boolean {
  const p = ipv4Parts(ip);
  if (!p) return true;
  if (p[0] === 0 || p[0] === 127) return true;
  if (p[0] === 169 && p[1] === 254) return true;
  // Docker-bruggen 172.17.0.0/16 t/m 172.31.0.0/16.
  if (p[0] === 172 && p[1] >= 17 && p[1] <= 31) return true;
  return false;
}

function skippedIface(name: string): boolean {
  return (
    !name ||
    name === "lo" ||
    name === "docker0" ||
    name.startsWith("br-") ||
    name.startsWith("veth") ||
    name.startsWith("docker")
  );
}

async function ipJson(args: string[]): Promise<unknown> {
  const { stdout } = await execFileAsync("ip", ["-j", ...args], {
    timeout: 4000,
    maxBuffer: 256 * 1024
  });
  return JSON.parse(stdout || "[]") as unknown;
}

function readDns(): string[] {
  try {
    const text = fs.readFileSync("/etc/resolv.conf", "utf8");
    const out: string[] = [];
    for (const line of text.split("\n")) {
      const m = /^\s*nameserver\s+(\S+)/.exec(line);
      if (m && isIpv4(m[1]) && !out.includes(m[1])) out.push(m[1]);
    }
    return out.slice(0, 2);
  } catch {
    return [];
  }
}

function readNetworkError(): string | null {
  try {
    const j = JSON.parse(fs.readFileSync(fileOf(ERROR_FILE), "utf8")) as { message?: unknown };
    return typeof j.message === "string" && j.message.trim() ? j.message.trim() : null;
  } catch {
    return null;
  }
}

function readPending(): PendingFile | null {
  try {
    const raw = fs.readFileSync(fileOf(PENDING), "utf8");
    return JSON.parse(raw) as PendingFile;
  } catch {
    return null;
  }
}

function requestHitsNewAddress(
  pending: PendingFile,
  hostHeader: string | undefined,
  localAddress: string | undefined
): boolean {
  if (pending.applied === false) return false;
  const want = (pending.address || "").trim();
  const local = (localAddress || "").replace(/^::ffff:/, "");
  const host = (hostHeader || "").split(":")[0].trim();
  if (pending.mode === "static") {
    return Boolean(want) && (host === want || local === want);
  }
  // DHCP dat hetzelfde adres houdt, bevestig je door de pagina opnieuw te openen.
  if (want && want === (pending.previousAddress || "").trim()) {
    return Boolean(local);
  }
  return Boolean(want) && (host === want || local === want);
}

function writeConfirm(by: string): void {
  const body = JSON.stringify({ at: new Date().toISOString(), by }, null, 2) + "\n";
  const dir = dataDir();
  fs.mkdirSync(dir, { recursive: true });
  const tmp = fileOf(CONFIRM + ".tmp");
  fs.writeFileSync(tmp, body, { mode: 0o666 });
  fs.renameSync(tmp, fileOf(CONFIRM));
}

/** Installer opent het nieuwe adres: dat is de bevestiging. */
export function confirmHostNetworkIfReached(
  by: string,
  hostHeader: string | undefined,
  localAddress: string | undefined
): void {
  const pending = readPending();
  if (!pending) return;
  if (!requestHitsNewAddress(pending, hostHeader, localAddress)) return;
  try {
    writeConfirm(by);
  } catch (err) {
    console.warn("[host-network] confirm schrijven mislukt:", err);
  }
}

export async function readHostNetwork(): Promise<HostNetworkView> {
  const pending = readPending();
  const base: HostNetworkView = {
    available: false,
    iface: null,
    mode: null,
    address: null,
    prefix: null,
    gateway: null,
    dns: [],
    pending: Boolean(pending),
    deadline: pending?.deadline ?? null,
    message: pending
      ? "Nieuw adres wordt gecontroleerd. Open het binnen 2 minuten, anders gaat het oude terug."
      : readNetworkError()
  };
  try {
    const routes = (await ipJson(["-4", "route", "show", "default"])) as Array<{
      dev?: string;
      gateway?: string;
    }>;
    const route = routes.find((r) => r.dev && !skippedIface(r.dev));
    if (!route?.dev) {
      return { ...base, message: base.message ?? "Geen netwerkkaart met een standaardroute." };
    }
    const addrs = (await ipJson(["-4", "addr", "show", "dev", route.dev])) as Array<{
      addr_info?: Array<{ family?: string; local?: string; prefixlen?: number; dynamic?: boolean }>;
    }>;
    const info = addrs
      .flatMap((a) => a.addr_info ?? [])
      .find((a) => a.family === "inet" && a.local && !unusableAddress(a.local));
    return {
      ...base,
      available: true,
      iface: route.dev,
      mode: info?.dynamic === false ? "static" : "dhcp",
      address: info?.local ?? null,
      prefix: typeof info?.prefixlen === "number" ? info.prefixlen : null,
      gateway: route.gateway && isIpv4(route.gateway) ? route.gateway : null,
      dns: readDns()
    };
  } catch {
    return {
      ...base,
      message: base.message ?? "Dit paneel werkt alleen op de server zelf."
    };
  }
}

export type NetworkRequestResult =
  | { ok: true }
  | { ok: false; status: number; error: string; message: string };

export function requestHostNetwork(input: {
  mode: HostNetworkMode;
  address?: string;
  prefix?: number;
  gateway?: string;
  dns?: string[];
  by: string;
}): NetworkRequestResult {
  if (!readServerUpdateStatus().agentReady) {
    return {
      ok: false,
      status: 503,
      error: "agent_offline",
      message: "De server kan het netwerk nu niet wijzigen. Wacht een halve minuut en probeer opnieuw."
    };
  }
  const pending = readPending();
  if (pending) {
    return {
      ok: false,
      status: 409,
      error: "network_pending",
      message: "Er loopt al een netwerkwijziging. Wacht tot die klaar is of teruggedraaid."
    };
  }
  const dns = (input.dns ?? []).map((d) => d.trim()).filter(Boolean).slice(0, 2);
  if (dns.some((d) => !isIpv4(d) || d.startsWith("127.") || d.startsWith("0.") || d.startsWith("169.254."))) {
    return {
      ok: false,
      status: 400,
      error: "bad_dns",
      message: "DNS moet een geldig IPv4-adres zijn."
    };
  }
  const body: Record<string, unknown> = {
    mode: input.mode,
    by: input.by,
    requestedAt: new Date().toISOString()
  };
  if (input.mode === "static") {
    const address = (input.address || "").trim();
    const gateway = (input.gateway || "").trim();
    const prefix = input.prefix;
    if (!isIpv4(address) || unusableAddress(address)) {
      return {
        ok: false,
        status: 400,
        error: "bad_address",
        message: "Kies een gewoon LAN-adres. Geen 127.0.0.1 en geen Docker-adres."
      };
    }
    if (typeof prefix !== "number" || !Number.isInteger(prefix) || prefix < 8 || prefix > 30) {
      return {
        ok: false,
        status: 400,
        error: "bad_prefix",
        message: "Het netmasker moet tussen /8 en /30 liggen."
      };
    }
    if (!isIpv4(gateway) || unusableAddress(gateway)) {
      return {
        ok: false,
        status: 400,
        error: "bad_gateway",
        message: "De gateway moet een gewoon IPv4-adres zijn."
      };
    }
    if (!sameSubnet(address, gateway, prefix)) {
      return {
        ok: false,
        status: 400,
        error: "gateway_subnet",
        message: "De gateway moet in hetzelfde net zitten als het adres."
      };
    }
    if (address === gateway) {
      return {
        ok: false,
        status: 400,
        error: "bad_gateway",
        message: "Het adres en de gateway mogen niet hetzelfde zijn."
      };
    }
    body.address = address;
    body.prefix = prefix;
    body.gateway = gateway;
    body.dns = dns.length > 0 ? dns : [gateway];
  }
  const dir = dataDir();
  fs.mkdirSync(dir, { recursive: true });
  try {
    fs.unlinkSync(fileOf(ERROR_FILE));
  } catch {
    /* ignore */
  }
  const tmp = fileOf(REQUEST + ".tmp");
  fs.writeFileSync(tmp, JSON.stringify(body, null, 2) + "\n", { mode: 0o666 });
  fs.renameSync(tmp, fileOf(REQUEST));
  return { ok: true };
}
