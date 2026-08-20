import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";

export type ServerUpdateState =
  | "idle"
  | "queued"
  | "running"
  | "success"
  | "error";

export interface ServerUpdateStatus {
  state: ServerUpdateState;
  step: string | null;
  message: string;
  error: string | null;
  requestedBy: string | null;
  requestedAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  agentHeartbeatAt: string | null;
  agentReady: boolean;
}

const HEARTBEAT_MS = 20_000;
const RUNNING_STALE_MS = 45 * 60 * 1000;

function dataDir(): string {
  const fromEnv = process.env.LOG_STORE_PATH?.trim();
  if (fromEnv) return path.dirname(path.resolve(fromEnv));
  return path.join(process.cwd(), "data");
}

export function updateStatusPath(): string {
  return path.join(dataDir(), "update-status.json");
}

export function updateRequestPath(): string {
  return path.join(dataDir(), "update-request.json");
}

function parseState(raw: unknown): ServerUpdateState {
  switch (raw) {
    case "idle":
    case "queued":
    case "running":
    case "success":
    case "error":
      return raw;
    default:
      return "idle";
  }
}

function str(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length ? t : null;
}

function agentReadyFrom(s: Omit<ServerUpdateStatus, "agentReady">): boolean {
  const hb = s.agentHeartbeatAt ? Date.parse(s.agentHeartbeatAt) : NaN;
  if (Number.isFinite(hb) && Date.now() - hb < HEARTBEAT_MS) return true;
  if (s.state === "running" || s.state === "queued") {
    const t = s.startedAt ?? s.requestedAt;
    const ms = t ? Date.parse(t) : NaN;
    if (Number.isFinite(ms) && Date.now() - ms < RUNNING_STALE_MS) return true;
  }
  return false;
}

export function readServerUpdateStatus(): ServerUpdateStatus {
  const empty: Omit<ServerUpdateStatus, "agentReady"> = {
    state: "idle",
    step: null,
    message: "",
    error: null,
    requestedBy: null,
    requestedAt: null,
    startedAt: null,
    finishedAt: null,
    agentHeartbeatAt: null
  };
  let base = empty;
  try {
    const raw = fs.readFileSync(updateStatusPath(), "utf-8");
    const j = JSON.parse(raw) as Record<string, unknown>;
    base = {
      state: parseState(j.state),
      step: str(j.step),
      message: str(j.message) ?? "",
      error: str(j.error),
      requestedBy: str(j.requestedBy),
      requestedAt: str(j.requestedAt),
      startedAt: str(j.startedAt),
      finishedAt: str(j.finishedAt),
      agentHeartbeatAt: str(j.agentHeartbeatAt)
    };
  } catch {
    base = empty;
  }
  try {
    if (
      fs.existsSync(updateRequestPath()) &&
      base.state !== "running" &&
      base.state !== "queued"
    ) {
      base = {
        ...base,
        state: "queued",
        message: base.message || "Update aangevraagd. Even geduld…"
      };
    }
  } catch {
    /* ignore */
  }
  return { ...base, agentReady: agentReadyFrom(base) };
}

export function requestServerUpdate(requestedBy: string): {
  ok: true;
  status: ServerUpdateStatus;
} | { ok: false; status: number; error: string; message: string } {
  const current = readServerUpdateStatus();
  if (!current.agentReady && current.state !== "running") {
    return {
      ok: false,
      status: 503,
      error: "update_agent_unavailable",
      message:
        "De update-agent draait niet. Eenmalig op de NUC: sudo bash docker/install.sh"
    };
  }
  if (current.state === "running" || current.state === "queued") {
    return {
      ok: false,
      status: 409,
      error: "update_already_running",
      message: current.message || "Er loopt al een update."
    };
  }

  const now = new Date().toISOString();
  const request = {
    requestedAt: now,
    requestedBy
  };
  try {
    fs.mkdirSync(dataDir(), { recursive: true });
    fs.writeFileSync(
      updateRequestPath(),
      `${JSON.stringify(request, null, 2)}\n`,
      "utf-8"
    );
    logger.warn({ requestedBy }, "admin requested GitHub server update");
    return { ok: true, status: readServerUpdateStatus() };
  } catch (err) {
    logger.warn({ err }, "update-request schrijven mislukt");
    return {
      ok: false,
      status: 500,
      error: "update_request_failed",
      message: "Kon de update-opdracht niet wegschrijven."
    };
  }
}
