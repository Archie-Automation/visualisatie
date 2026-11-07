import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";
import { remoteUrl } from "./remoteAccess";

export type RemoteEnrollState = "idle" | "queued" | "running" | "success" | "error";

export interface RemoteEnrollStatus {
  state: RemoteEnrollState;
  message: string;
  error: string | null;
  remoteUrl: string | null;
}

const CODE_RE = /^[A-Z0-9]{4}-[A-Z0-9]{4}$/;

function dataDir(): string {
  const fromEnv = process.env.LOG_STORE_PATH?.trim();
  if (fromEnv) return path.dirname(path.resolve(fromEnv));
  return path.join(process.cwd(), "data");
}

function statusPath(): string {
  return path.join(dataDir(), "enroll-status.json");
}

function requestPath(): string {
  return path.join(dataDir(), "enroll-request.json");
}

function parseState(raw: unknown): RemoteEnrollState {
  switch (raw) {
    case "queued":
    case "running":
    case "success":
    case "error":
      return raw;
    default:
      return "idle";
  }
}

export function normalizeEnrollCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.trim().toUpperCase();
  return CODE_RE.test(code) ? code : null;
}

export function readRemoteEnrollStatus(): RemoteEnrollStatus {
  const live = remoteUrl();
  let state: RemoteEnrollState = "idle";
  let message = "";
  let error: string | null = null;
  let fromFile: string | null = null;
  try {
    const j = JSON.parse(fs.readFileSync(statusPath(), "utf-8")) as Record<string, unknown>;
    state = parseState(j.state);
    message = typeof j.message === "string" ? j.message : "";
    error = typeof j.error === "string" && j.error.trim() ? j.error.trim() : null;
    fromFile = typeof j.remoteUrl === "string" && j.remoteUrl.trim() ? j.remoteUrl.trim() : null;
  } catch {
    /* nog geen koppeling geprobeerd */
  }
  if (fs.existsSync(requestPath()) && state !== "running" && state !== "queued") {
    state = "queued";
    message = message || "Code ontvangen. Even geduld…";
  }
  return {
    state,
    message,
    error,
    remoteUrl: live ?? fromFile
  };
}

export function requestRemoteEnroll(code: string, requestedBy: string):
  | { ok: true; status: RemoteEnrollStatus }
  | { ok: false; status: number; error: string; message: string } {
  const current = readRemoteEnrollStatus();
  if (current.state === "running" || current.state === "queued") {
    return {
      ok: false,
      status: 409,
      error: "enroll_busy",
      message: "Er loopt al een koppeling."
    };
  }
  const now = new Date().toISOString();
  try {
    fs.mkdirSync(dataDir(), { recursive: true });
    fs.writeFileSync(
      requestPath(),
      `${JSON.stringify({ code, requestedBy, requestedAt: now }, null, 2)}\n`,
      { encoding: "utf-8", mode: 0o644 }
    );
    fs.writeFileSync(
      statusPath(),
      `${JSON.stringify({
        state: "queued",
        message: "Code ontvangen. De server koppelt zichzelf…",
        error: null,
        remoteUrl: current.remoteUrl,
        requestedAt: now
      }, null, 2)}\n`,
      "utf-8"
    );
    logger.warn({ requestedBy }, "installer requested cloud enroll");
    return { ok: true, status: readRemoteEnrollStatus() };
  } catch (err) {
    logger.warn({ err }, "enroll-request schrijven mislukt");
    return {
      ok: false,
      status: 500,
      error: "enroll_write_failed",
      message: "De code kon niet worden bewaard."
    };
  }
}
