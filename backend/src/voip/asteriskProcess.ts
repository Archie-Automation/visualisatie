import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { logger } from "../logger";

export type AsteriskProcessState = "started" | "running" | "disabled";

export interface AsteriskProcessStatus {
  autoStart: boolean;
  running: boolean;
  pid: number | null;
  restarts: number;
  lastExit: { code: number | null; signal: string | null; at: string } | null;
  lastError: string | null;
  recent: string[];
}

let child: ChildProcess | null = null;
let confFile: string | null = null;
let restartEnabled = false;
let restartDelay = 2_000;
let restartTimer: ReturnType<typeof setTimeout> | null = null;
let hooksRegistered = false;
let restarts = 0;
let lastExit: AsteriskProcessStatus["lastExit"] = null;
let lastError: string | null = null;
const recent: string[] = [];

const RUNTIME_DIRS = [
  "/var/run/asterisk",
  "/var/log/asterisk",
  "/var/spool/asterisk",
  "/var/lib/asterisk"
];

/** ASTERISK_AUTO_START=1 in de NUC-image; lokaal (Windows) staat het uit. */
export function asteriskAutoStart(): boolean {
  const v = process.env.ASTERISK_AUTO_START?.trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes" || v === "on";
}

function remember(line: string): void {
  const t = line.trim();
  if (!t) return;
  recent.push(t.slice(0, 300));
  while (recent.length > 20) recent.shift();
}

function onOutput(stream: "stdout" | "stderr", buf: Buffer): void {
  for (const line of buf.toString("utf8").split(/\r?\n/)) {
    if (!line.trim()) continue;
    remember(line);
    if (stream === "stderr" || /ERROR|WARNING/.test(line)) {
      logger.warn({ asterisk: line }, "asterisk");
    } else {
      logger.debug({ asterisk: line }, "asterisk");
    }
  }
}

function registerExitHooks(): void {
  if (hooksRegistered) return;
  hooksRegistered = true;
  const down = () => stopAsteriskProcess();
  process.on("exit", down);
  process.on("SIGINT", down);
  process.on("SIGTERM", down);
}

function launch(conf: string): void {
  for (const d of RUNTIME_DIRS) {
    try {
      fs.mkdirSync(d, { recursive: true });
    } catch {
      /* ignore */
    }
  }
  const bin = process.env.ASTERISK_BIN?.trim() || "asterisk";
  // -f: voorgrond (kind van de backend), -C: config uit de data-map.
  const proc = spawn(bin, ["-f", "-C", conf], {
    stdio: ["ignore", "pipe", "pipe"],
    detached: false
  });
  child = proc;
  lastError = null;
  proc.stdout?.on("data", (d: Buffer) => onOutput("stdout", d));
  proc.stderr?.on("data", (d: Buffer) => onOutput("stderr", d));
  proc.on("error", (err) => {
    lastError = err.message;
    logger.error({ err, bin }, "Asterisk starten mislukt");
    if (child === proc) child = null;
  });
  proc.on("exit", (code, signal) => {
    if (child === proc) child = null;
    lastExit = { code, signal, at: new Date().toISOString() };
    logger.warn({ code, signal }, "Asterisk gestopt");
    if (!restartEnabled || !confFile) return;
    const delay = restartDelay;
    restartDelay = Math.min(restartDelay * 2, 60_000);
    restartTimer = setTimeout(() => {
      restartTimer = null;
      if (restartEnabled && confFile && !child) {
        restarts += 1;
        launch(confFile);
      }
    }, delay);
  });
  logger.info({ bin, conf, pid: proc.pid }, "Asterisk gestart door backend");
}

/** Start Asterisk als kindproces als het nog niet draait. */
export function ensureAsteriskProcess(confDir: string): AsteriskProcessState {
  if (!asteriskAutoStart()) return "disabled";
  const conf = path.join(confDir, "asterisk.conf");
  confFile = conf;
  restartEnabled = true;
  if (child) return "running";
  registerExitHooks();
  restartDelay = 2_000;
  if (restartTimer) {
    clearTimeout(restartTimer);
    restartTimer = null;
  }
  launch(conf);
  return "started";
}

export function stopAsteriskProcess(): void {
  restartEnabled = false;
  if (restartTimer) {
    clearTimeout(restartTimer);
    restartTimer = null;
  }
  const c = child;
  child = null;
  if (!c) return;
  try {
    c.kill("SIGTERM");
  } catch {
    /* ignore */
  }
}

export function asteriskProcessStatus(): AsteriskProcessStatus {
  return {
    autoStart: asteriskAutoStart(),
    running: child !== null && child.exitCode === null,
    pid: child?.pid ?? null,
    restarts,
    lastExit,
    lastError,
    recent: [...recent]
  };
}
