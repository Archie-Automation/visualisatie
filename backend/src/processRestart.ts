import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";
import { stopGo2rtcChild } from "./go2rtcSpawn";

export function isDockerRuntime(): boolean {
  try {
    return fs.existsSync("/.dockerenv");
  } catch {
    return false;
  }
}

/**
 * Detect whether this process was started via ts-node-dev / npm run dev.
 * When true, restart by spawning "npm run dev" so ts-node-dev keeps ownership of
 * the port. Spawning "node dist/index.js" while ts-node-dev is running causes
 * an EADDRINUSE conflict on the next file-change restart.
 */
function isDevMode(): boolean {
  // ts-node-dev rewrites argv[1] to the source file path; dist/index.js means prod.
  const entry = process.argv[1] ?? "";
  if (entry.includes("dist/index.js")) return false;
  // Also treat NODE_ENV=production as prod.
  if (process.env.NODE_ENV === "production") return false;
  return true;
}

/**
 * Start een losgekoppeld vervangend backend-proces en stop daarna het huidige.
 * In dev-modus (ts-node-dev) altijd "npm run dev" gebruiken om poortconflicten
 * te voorkomen; in productie "node dist/index.js".
 */
export function exitAndSpawnReplacement(): void {
  const cwd = process.cwd();
  const distEntry = path.join(cwd, "dist", "index.js");
  const hasDist = fs.existsSync(distEntry);
  const dev = isDevMode();

  if (hasDist && !dev) {
    spawnDelayedNode(distEntry);
    logger.info({ via: "node dist/index.js" }, "Vervangend backend-proces gepland");
  } else {
    spawnDelayedNpmDev();
    logger.info({ via: "npm run dev" }, "Vervangend backend-proces gepland");
  }

  setTimeout(() => {
    try {
      stopGo2rtcChild();
    } catch (err) {
      logger.warn({ err }, "go2rtc stop voor exit");
    }
    process.exit(0);
  }, 300);
}

function spawnDelayedNode(entry: string): void {
  const cwd = process.cwd();
  const node = process.execPath;
  const script = `
setTimeout(function () {
  var cp = require("child_process");
  var p = cp.spawn(${JSON.stringify(node)}, [${JSON.stringify(entry)}], {
    cwd: ${JSON.stringify(cwd)},
    detached: true,
    stdio: "ignore",
    windowsHide: true,
    env: process.env
  });
  p.unref();
}, 2000);
`;
  spawn(node, ["-e", script], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  }).unref();
}

function spawnDelayedNpmDev(): void {
  const cwd = process.cwd();
  const node = process.execPath;
  const npm = process.platform === "win32" ? "npm.cmd" : "npm";
  const script = `
setTimeout(function () {
  var cp = require("child_process");
  var p = cp.spawn(${JSON.stringify(npm)}, ["run", "dev"], {
    cwd: ${JSON.stringify(cwd)},
    detached: true,
    stdio: "ignore",
    windowsHide: true,
    shell: ${JSON.stringify(process.platform === "win32")},
    env: process.env
  });
  p.unref();
}, 2000);
`;
  spawn(node, ["-e", script], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  }).unref();
}

/** Docker: container herstart via restart-beleid. Lokaal: spawn + exit. */
export function scheduleAdminProcessRestart(): void {
  if (isDockerRuntime()) {
    logger.info("Docker: backend-proces wordt beëindigd voor container-herstart");
    setTimeout(() => {
      try {
        stopGo2rtcChild();
      } catch (err) {
        logger.warn({ err }, "go2rtc stop voor exit");
      }
      process.exit(0);
    }, 500);
    return;
  }
  exitAndSpawnReplacement();
}
