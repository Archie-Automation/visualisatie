import { spawn, type ChildProcess } from "node:child_process";
import path from "node:path";
import { logger } from "./logger";

let child: ChildProcess | null = null;
let hooksRegistered = false;
let _restartEnabled = false;
let _restartDelay = 2_000;
let _configPath: string | null = null;

function envTruthy(name: string, defaultWhenUnset: boolean): boolean {
  const v = process.env[name];
  if (v === undefined || v === "") return defaultWhenUnset;
  const s = v.trim().toLowerCase();
  if (["0", "false", "no", "off"].includes(s)) return false;
  if (["1", "true", "yes", "on"].includes(s)) return true;
  return defaultWhenUnset;
}

/** GO2RTC_AUTO_START=1/true/yes/on starts go2rtc when GO2RTC_CONFIG_PATH is set (default off if unset). */
function shouldAutoStartGo2rtc(): boolean {
  const hasPath = !!process.env.GO2RTC_CONFIG_PATH?.trim();
  if (!hasPath) return false;
  return envTruthy("GO2RTC_AUTO_START", false);
}

function go2rtcBinary(): string {
  const fromEnv = process.env.GO2RTC_BIN?.trim();
  if (fromEnv) return fromEnv;
  return process.platform === "win32" ? "go2rtc.exe" : "go2rtc";
}

function resolveConfigPath(configPath: string): string {
  return path.isAbsolute(configPath)
    ? configPath
    : path.resolve(process.cwd(), configPath);
}

function registerExitHooks(): void {
  if (hooksRegistered) return;
  hooksRegistered = true;
  const down = () => {
    stopGo2rtcChild();
  };
  process.on("exit", down);
  process.on("SIGINT", down);
  process.on("SIGTERM", down);
  process.on("SIGBREAK", down);
}

function logChunk(stream: "stdout" | "stderr", buf: Buffer): void {
  const text = buf.toString("utf8").trimEnd();
  if (!text) return;
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    if (stream === "stderr") {
      logger.warn({ go2rtc: line }, "go2rtc stderr");
    } else {
      logger.debug({ go2rtc: line }, "go2rtc stdout");
    }
  }
}

export function stopGo2rtcChild(): void {
  _restartEnabled = false;
  if (!child) return;
  const c = child;
  child = null;
  try {
    c.kill("SIGTERM");
  } catch {
    /* ignore */
  }
}

function startGo2rtcProcess(bin: string, absConfig: string): void {
  const proc = spawn(bin, ["-config", absConfig], {
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
    detached: false
  });
  child = proc;

  proc.stdout?.on("data", (d: Buffer) => logChunk("stdout", d));
  proc.stderr?.on("data", (d: Buffer) => logChunk("stderr", d));

  proc.on("error", (err) => {
    logger.error(
      { err, bin },
      "go2rtc start mislukt (staat het executable op PATH of is GO2RTC_BIN gezet?)"
    );
    if (child === proc) child = null;
  });

  proc.on("exit", (code, signal) => {
    if (child === proc) child = null;
    if (code !== 0 && code !== null) {
      logger.warn({ code, signal }, "go2rtc proces beëindigd met foutcode");
    } else {
      logger.info({ code, signal }, "go2rtc proces beëindigd");
    }
    // Auto-restart with exponential backoff unless deliberately stopped.
    if (_restartEnabled && child === null && _configPath) {
      const delay = _restartDelay;
      _restartDelay = Math.min(_restartDelay * 2, 60_000);
      logger.info({ delayMs: delay }, "go2rtc herstart over");
      setTimeout(() => {
        if (_restartEnabled && _configPath) {
          _restartDelay = 2_000;
          startGo2rtcProcess(go2rtcBinary(), _configPath);
        }
      }, delay);
    }
  });

  logger.info(
    { bin, config: absConfig },
    "go2rtc gestart door backend (zelfde machine als API)"
  );
}

/**
 * Start or stop the go2rtc child process after house config / yaml was written.
 * Intended so developers do not run a separate go2rtc container manually.
 * Keeps go2rtc alive with exponential-backoff auto-restart.
 */
export function syncGo2rtcProcessAfterConfigWritten(
  configPath: string | null
): void {
  if (!shouldAutoStartGo2rtc()) {
    stopGo2rtcChild();
    return;
  }
  if (!configPath) {
    logger.warn(
      "GO2RTC_AUTO_START staat aan maar GO2RTC_CONFIG_PATH ontbreekt – go2rtc niet gestart"
    );
    stopGo2rtcChild();
    return;
  }

  registerExitHooks();
  stopGo2rtcChild(); // clears old process; also sets _restartEnabled=false

  const absConfig = resolveConfigPath(configPath);
  _configPath = absConfig;
  _restartEnabled = true;
  _restartDelay = 2_000;

  startGo2rtcProcess(go2rtcBinary(), absConfig);
}
