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
/** Agent heeft de opdracht niet opgepakt. Langer dan dit is de code toch al verlopen. */
const QUEUED_STALE_MS = 2 * 60 * 1000;
const RUNNING_STALE_MS = 10 * 60 * 1000;
const STALE_MESSAGE =
  "De vorige koppeling is blijven hangen. Die is gestopt. Vraag een nieuwe code en vul die in.";

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

function loosen(file: string): void {
  try {
    if (fs.existsSync(file)) fs.chmodSync(file, 0o666);
  } catch {
    /* host-agent moet het bestand ook kunnen overschrijven */
  }
}

function writeJson(file: string, value: unknown): void {
  fs.mkdirSync(dataDir(), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf-8",
    mode: 0o666
  });
  loosen(file);
}

function readStatusFile(): {
  state: RemoteEnrollState;
  message: string;
  error: string | null;
  remoteUrl: string | null;
  requestedAt: string | null;
  updatedAt: string | null;
} {
  try {
    const j = JSON.parse(fs.readFileSync(statusPath(), "utf-8")) as Record<string, unknown>;
    return {
      state: parseState(j.state),
      message: typeof j.message === "string" ? j.message : "",
      error: typeof j.error === "string" && j.error.trim() ? j.error.trim() : null,
      remoteUrl: typeof j.remoteUrl === "string" && j.remoteUrl.trim() ? j.remoteUrl.trim() : null,
      requestedAt: typeof j.requestedAt === "string" ? j.requestedAt : null,
      updatedAt: typeof j.updatedAt === "string" ? j.updatedAt : null
    };
  } catch {
    return {
      state: "idle",
      message: "",
      error: null,
      remoteUrl: null,
      requestedAt: null,
      updatedAt: null
    };
  }
}

function ageMs(iso: string | null): number | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  return Date.now() - t;
}

/** Een blijven-hangen "queued" blokkeert elke nieuwe code. Zet die terug naar een fout. */
export function releaseStuckRemoteEnroll(): void {
  loosen(statusPath());
  loosen(requestPath());
  const current = readStatusFile();
  const age = ageMs(current.requestedAt);
  const runningAge = ageMs(current.updatedAt) ?? age;
  const queuedStuck =
    current.state === "queued" && (age === null || age > QUEUED_STALE_MS);
  const runningStuck =
    current.state === "running" && runningAge !== null && runningAge > RUNNING_STALE_MS;
  if (!queuedStuck && !runningStuck) {
    if (current.state === "error" && fs.existsSync(requestPath())) {
      try {
        fs.unlinkSync(requestPath());
      } catch {
        /* agent ruimt het later op */
      }
    }
    return;
  }
  try {
    if (fs.existsSync(requestPath())) fs.unlinkSync(requestPath());
  } catch {
    /* request kan blijven liggen; de status is leidend */
  }
  try {
    writeJson(statusPath(), {
      state: "error",
      message: STALE_MESSAGE,
      error: "stale",
      remoteUrl: current.remoteUrl,
      requestedAt: current.requestedAt
    });
  } catch (err) {
    logger.warn({ err }, "vastgelopen koppeling opruimen mislukt");
  }
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
  releaseStuckRemoteEnroll();
  const live = remoteUrl();
  const file = readStatusFile();
  return {
    state: file.state,
    message: file.message,
    error: file.error,
    remoteUrl: live ?? file.remoteUrl
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
      message: "Er loopt al een koppeling. Wacht twee minuten en vul de code opnieuw in."
    };
  }
  const now = new Date().toISOString();
  try {
    writeJson(requestPath(), { code, requestedBy, requestedAt: now });
    writeJson(statusPath(), {
      state: "queued",
      message: "Code ontvangen. De server koppelt zichzelf…",
      error: null,
      remoteUrl: current.remoteUrl,
      requestedAt: now
    });
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
