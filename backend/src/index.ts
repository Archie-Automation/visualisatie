import dotenv from "dotenv";
dotenv.config({ quiet: true });
import http from "node:http";
import path from "node:path";
import fs from "node:fs";
import express from "express";
import cors from "cors";
import { logger } from "./logger";
import { collectAllGAs, loadConfig } from "./config";
import { KnxBus } from "./knxBus";
import { buildRouter } from "./routes";
import { LogStore } from "./logStore";
import { startLogSampler } from "./logSampler";
import { startScheduler } from "./scheduler";
import { attachWebSocket } from "./ws";
import { writeGo2rtcConfig } from "./cameras";
import { startCameraSnapshotWarmer, startGo2rtcStreamKeeper } from "./cameraSnapshot";
import { syncGo2rtcProcessAfterConfigWritten } from "./go2rtcSpawn";
import { MediaManager } from "./media/manager";
import { LutronIntegrationManager } from "./lutron/manager";
import {
  getConnectivitySnapshot,
  logStartupConnectivityReport
} from "./startupConnectivity";
import { appVersionInfo } from "./version";

function main() {
  const cfg = loadConfig();
  let go2rtcYaml: string | null = null;
  try {
    go2rtcYaml = writeGo2rtcConfig(cfg);
  } catch (err) {
    logger.warn({ err }, "go2rtc-config schrijven mislukt - backend start verder zonder");
  }
  syncGo2rtcProcessAfterConfigWritten(go2rtcYaml);

  const knxEnabled = cfg.knx !== undefined && cfg.knx.enabled !== false;
  const host = process.env.KNX_GATEWAY_HOST ?? cfg.knx?.gateway?.host ?? "127.0.0.1";
  const port = Number(process.env.KNX_GATEWAY_PORT ?? cfg.knx?.gateway?.port ?? 3671);

  const bus = new KnxBus(host, port, cfg.knx?.physicalAddress, !knxEnabled);

  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "10mb" }));

  // ── Serve Flutter web build ────────────────────────────────────────────────
  // WEB_ROOT: absolute path in Docker (/app/web). Dev default: ../app/build/web.
  const webBuildDir = (process.env.WEB_ROOT?.trim() ||
    path.join(process.cwd(), "..", "app", "build", "web")).replace(/\/+$/, "");
  const webIndexHtml = path.join(webBuildDir, "index.html");
  if (fs.existsSync(webBuildDir)) {
    const webNoCache = new Set([
      "index.html",
      "main.dart.js",
      "flutter_bootstrap.js",
      "flutter_service_worker.js",
      "version.json",
    ]);
    const devMode = process.env.NODE_ENV !== "production";
    app.use(
      express.static(webBuildDir, {
        setHeaders(res, filePath) {
          if (devMode || webNoCache.has(path.basename(filePath))) {
            res.setHeader("Cache-Control", "no-cache, must-revalidate");
          }
        },
      })
    );
    if (devMode) {
      const webMainJs = path.join(webBuildDir, "main.dart.js");
      if (fs.existsSync(webMainJs)) {
        const buildMtime = fs.statSync(webMainJs).mtimeMs;
        const libDir = path.join(process.cwd(), "..", "app", "lib");
        let newestSource = 0;
        const walk = (dir: string) => {
          for (const name of fs.readdirSync(dir)) {
            const full = path.join(dir, name);
            const st = fs.statSync(full);
            if (st.isDirectory()) walk(full);
            else if (name.endsWith(".dart") && st.mtimeMs > newestSource) {
              newestSource = st.mtimeMs;
            }
          }
        };
        if (fs.existsSync(libDir)) walk(libDir);
        if (newestSource > buildMtime) {
          logger.warn(
            {
              buildAge: new Date(buildMtime).toISOString(),
              sourceAge: new Date(newestSource).toISOString(),
            },
            "Flutter web build is ouder dan broncode — telefoon/PWA ziet nog oude UI. Voer uit: npm run refresh:phone"
          );
        }
      }
    }
    logger.info(
      { dir: webBuildDir, appVersion: appVersionInfo.version },
      "Flutter web build wordt geserveerd"
    );
  } else {
    app.get("/", (_req, res) => {
      res
        .type("html")
        .send(
          `<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Archie OS</title>
<style>body{font-family:system-ui;max-width:36rem;margin:2rem auto;padding:0 1rem;line-height:1.6}</style>
</head><body>
<h2>Archie OS — API actief</h2>
<p>De Flutter-app is nog niet gebouwd. Voer het volgende uit om de web-app klaar te maken:</p>
<pre style="background:#f4f4f4;padding:1rem;border-radius:6px">npm run build:web</pre>
<p>Daarna is de app beschikbaar op <strong>http://&lt;server&gt;:4000/</strong></p>
</body></html>`
        );
    });
  }

  const media = new MediaManager();
  media.rebuild(cfg);
  media.start();

  const lutron = new LutronIntegrationManager(bus);
  lutron.rebuild(cfg);

  const logStore = new LogStore();
  const logSampler = startLogSampler(bus, logStore);

  const server = http.createServer(app);
  const wsHub = attachWebSocket(server, bus, media);
  const scheduler = startScheduler(bus, media);
  app.use(
    "/api",
    buildRouter(bus, wsHub, scheduler, media, lutron, logStore, logSampler)
  );

  if (fs.existsSync(webIndexHtml)) {
    app.get("*", (_req, res) => {
      res.setHeader("Cache-Control", "no-cache, must-revalidate");
      res.sendFile(webIndexHtml);
    });
  }

  const listenPort = Number(process.env.PORT ?? 4000);
  const mediaBase = () =>
    (process.env.MEDIA_BASE_URL ?? "http://localhost:1984").replace(/\/+$/, "");
  const stopSnapshotWarmer = startCameraSnapshotWarmer(loadConfig, mediaBase);
  const stopStreamKeeper = startGo2rtcStreamKeeper(loadConfig, mediaBase);

  server.listen(listenPort, () => {
    logger.info({ port: listenPort }, "HTTP + WS server listening");
  });

  process.on("exit", () => {
    stopSnapshotWarmer();
    stopStreamKeeper();
  });

  void bus
    .connect(collectAllGAs(cfg))
    .then(() => {
      logger.info({ host, port }, "KNX-gateway verbonden.");
    })
    .catch((err: unknown) => {
      logger.error(
        { err, host, port },
        "KNX-gateway niet bereikbaar; bus blijft offline. API en overige diensten draaien wel."
      );
    });

  const reportMs = Number(process.env.STARTUP_CONNECTIVITY_REPORT_MS ?? 5000);
  setTimeout(() => {
    try {
      logStartupConnectivityReport(getConnectivitySnapshot(bus, media, lutron));
    } catch (err) {
      logger.warn({ err }, "Kon startup-connectivityrapport niet maken");
    }
  }, reportMs);
}

try {
  main();
} catch (err) {
  logger.fatal({ err }, "fatal startup error");
  process.exit(1);
}
