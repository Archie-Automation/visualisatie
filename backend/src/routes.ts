import { randomUUID } from "node:crypto";
import { Readable } from "node:stream";
import { Router } from "express";
import { z } from "zod";
import {
  authenticate,
  canEditScenes,
  canReleaseIntercom,
  canViewIntercom,
  currentUser,
  requireAdmin,
  requireAuth,
  requireStaff,
  type AuthedRequest
} from "./auth";
import { isStaffRole, normalizeRole } from "./roles";
import {
  assertUsersMutation,
  canonicalizeStoredUser,
  filterConfigForUser,
  houseFunctionAllowed,
  userMayUseDevice
} from "./userAccess";
import {
  collectAllGAs,
  findRoom,
  findScene,
  getConfig,
  getConfigVersion,
  loadConfig,
  persistConfig,
  updateConfig,
  walkDevices
} from "./config";
import { CommandSchema, dispatch } from "./commands";
import { findLogDef, listLogDefs } from "./logDefs";
import type { LogStore } from "./logStore";
import type { LogSamplerHandle } from "./logSampler";
import { hvacSwitchLock } from "./hvacSwitchLock";
import { fireplaceVirtual } from "./fireplaceVirtual";
import { probeSonos } from "./media/sonos";
import * as spotify from "./media/spotify";
import type { KnxBus } from "./knxBus";
import { logger } from "./logger";
import { runScene } from "./scenes";
import type { SchedulerHandle } from "./scheduler";
import type { HouseConfig, Scene, Schedule, User } from "./types";
import { appVersionInfo } from "./version";
import {
  fetchAndroidApkFromGithub,
  getGithubLatest,
  isUpdateAvailableOnGithub
} from "./githubLatest";
import { readServerUpdateStatus, requestServerUpdate } from "./serverUpdate";
import {
  cameraPath,
  collectCameras,
  collectIntercoms,
  publicCamera,
  publicIntercom,
  writeGo2rtcConfig
} from "./cameras";
import {
  refreshSnapshotCache,
  serveSnapshotFromCache,
  snapshotCache,
  triggerBackgroundSnapshotRefresh,
  warmGo2rtcProducer
} from "./cameraSnapshot";
import { syncGo2rtcProcessAfterConfigWritten } from "./go2rtcSpawn";
import { probeCameraStreams } from "./cameraProbe";
import { parseKnxExport, persistGaCatalog, loadGaCatalog } from "./knxImport";
import { scheduleAdminProcessRestart } from "./processRestart";
import { releaseDoor } from "./intercoms";
import type { MediaManager } from "./media/manager";
import type { LutronIntegrationManager } from "./lutron/manager";
import type { WsHub } from "./ws";
import { getConnectivitySnapshot } from "./startupConnectivity";
import { normalizeHouseCamerasRaw } from "./houseCameras";
import { normalizeHouseIntercomsRaw } from "./houseIntercoms";
import {
  applyPlaintextPasswords,
  assertUsersHaveHashes,
  mergePasswordHashes,
  mergeLutronTelnetPasswords,
  validateHouseJson,
  validateFireplaceSemantics,
  validateIntercomSemantics,
  validateRgbwWwSemantics,
  validateLutronSemantics,
  validateLutronLoadOutputSemantics
} from "./houseValidate";

function stripHash(u: User): User {
  // Keep the shape but blank out the hash. Clients should never see it.
  return { ...u, passwordHash: "" };
}

/** Short-lived OAuth `state` values for the Spotify login (CSRF guard). */
const spotifyAuthStates = new Set<string>();

/** HTTP origin of the Flutter app (never 127.0.0.1 when the request came via LAN). */
function httpAppHome(req: { get(h: string): string | undefined }): string {
  const httpPort = process.env.PORT ?? "4000";
  const host = (req.get("host") ?? "").replace(/:\d+$/, "");
  if (host && !spotify.isLoopbackUrl(`http://${host}`)) {
    return `http://${host}:${httpPort}`;
  }
  const env = (process.env.PUBLIC_API_BASE ?? "").replace(/\/+$/, "");
  if (env && !spotify.isLoopbackUrl(env)) {
    try {
      const u = new URL(env.includes("://") ? env : `http://${env}`);
      if (u.hostname && !spotify.isLoopbackUrl(u.origin)) {
        return `http://${u.hostname}:${httpPort}`;
      }
    } catch {
      /* ignore */
    }
  }
  return `http://127.0.0.1:${httpPort}`;
}

/** Minimal HTML page shown in the browser after the Spotify redirect. */
function spotifyResultPage(
  message: string,
  home?: string,
  autoRedirect = false
): string {
  const dest = (home ?? "").replace(/\/+$/, "");
  const refresh =
    autoRedirect && dest
      ? `<meta http-equiv="refresh" content="1;url=${dest}/">`
      : "";
  const back = dest
    ? `<p style="margin-top:1.25rem"><a href="${dest}/" style="color:#1db954">Terug naar de app</a></p>`
    : "";
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${refresh}
<title>Spotify</title>
<style>body{font-family:system-ui,sans-serif;background:#121212;color:#fff;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}
.card{max-width:420px;padding:2rem}h1{font-size:1.25rem;margin:0 0 .75rem}
p{color:#b3b3b3;margin:0}a{color:#1db954}</style></head>
<body><div class="card"><h1>Spotify</h1><p>${message}</p>${back}</div></body></html>`;
}

/**
 * Strip sensitive bits before shipping config to a client and apply
 * per-user ACLs. Camera/intercom credentials never leave the backend.
 */
function publicConfig(cfg: HouseConfig, role: string, userId?: string) {
  const { users, cameras = [], intercoms = [], ...rest } = cfg;
  const me = users?.find((u) => u.id === userId);
  // Ship only the current user, with passwordHash stripped, so the client
  // can render an accurate capability UI.
  const mePublic = me
    ? [
        stripHash({
          ...me,
          role: normalizeRole(me.role),
          enabled: me.enabled !== false
        })
      ]
    : [];
  // The stripping below removes fields that the Device types mark as
  // required (rtsp/sources on camera/intercom) – intentional, since the
  // client never needs those – so we force the TS shape back to
  // HouseConfig after construction.
  const lutronSafe =
    rest.lutron != null
      ? {
          ...rest.lutron,
          ...(rest.lutron.telnet
            ? { telnet: { ...rest.lutron.telnet, password: "" } }
            : {})
        }
      : undefined;

  const scrubbed = {
    ...rest,
    ...(lutronSafe ? { lutron: lutronSafe } : {}),
    users: mePublic,
    cameras: cameras.map((d) => {
      const { rtsp: _r, sources: _s, ...safe } = d.camera;
      return { ...d, camera: safe };
    }),
    intercoms: intercoms.map((d) => {
      const { rtsp: _r, sources: _s, ...restIc } = d.intercom;
      const doorbird = restIc.doorbird as
        | { password?: string; [k: string]: unknown }
        | undefined;
      const sip = restIc.sip as { password?: string; [k: string]: unknown } | undefined;
      const safeIntercom = {
        ...restIc,
        ...(doorbird && typeof doorbird === "object"
          ? { doorbird: { ...doorbird, password: "" } }
          : {}),
        ...(sip && typeof sip === "object" ? { sip: { ...sip, password: "" } } : {})
      } as typeof d.intercom;
      return { ...d, intercom: safeIntercom };
    }),
    floors: rest.floors.map((f) => ({
      ...f,
      rooms: f.rooms.map((room) => ({
        ...room,
        devices: room.devices.map((d) => {
          if (d.type === "lutron_homeworks") {
            const lh = d.lutronHomeworks;
            const tel = lh.telnet;
            if (!tel) return d;
            return {
              ...d,
              lutronHomeworks: {
                ...lh,
                telnet: { ...tel, password: "" }
              }
            };
          }
          return d;
        })
      }))
    }))
  } as unknown as HouseConfig;
  if (isStaffRole(role) || isStaffRole(me?.role) || !me?.access) return scrubbed;
  return filterConfigForUser(scrubbed, me);
}

/** Full house.json for the installer UI (no password hashes). */
function installerHouseForClient(cfg: HouseConfig): HouseConfig {
  const copy = structuredClone(cfg);
  if (copy.users) {
    for (const u of copy.users) u.passwordHash = "";
  }
  walkDevices(copy, (d) => {
    if (d.type !== "lutron_homeworks") return;
    const tel = d.lutronHomeworks.telnet;
    if (tel && tel.password != null) tel.password = "";
  });
  const hlTel = copy.lutron?.telnet;
  if (hlTel && hlTel.password != null) hlTel.password = "";
  return copy;
}

/** Parse an epoch-ms query param, falling back to `fallback`. */
function parseTs(raw: unknown, fallback: number): number {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

/** Parse a positive integer query param clamped to [min, max]. */
function parseIntRange(
  raw: unknown,
  fallback: number,
  min: number,
  max: number
): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(n)));
}

/** Sonos/TuneIn sometimes omit or mangle Content-Type; sniff magic bytes. */
function sniffImageContentType(
  buf: ArrayBuffer,
  declared: string
): string | null {
  const ct = declared.split(";")[0]?.trim().toLowerCase() ?? "";
  if (ct.startsWith("image/")) return ct;
  const u = new Uint8Array(buf);
  if (u.length >= 3 && u[0] === 0xff && u[1] === 0xd8 && u[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    u.length >= 8 &&
    u[0] === 0x89 &&
    u[1] === 0x50 &&
    u[2] === 0x4e &&
    u[3] === 0x47
  ) {
    return "image/png";
  }
  if (
    u.length >= 12 &&
    u[0] === 0x52 &&
    u[1] === 0x49 &&
    u[2] === 0x46 &&
    u[3] === 0x46 &&
    u[8] === 0x57 &&
    u[9] === 0x45 &&
    u[10] === 0x42 &&
    u[11] === 0x50
  ) {
    return "image/webp";
  }
  if (u.length >= 6 && u[0] === 0x47 && u[1] === 0x49 && u[2] === 0x46) {
    return "image/gif";
  }
  return null;
}

export function buildRouter(
  bus: KnxBus,
  ws: WsHub,
  scheduler: SchedulerHandle,
  media: MediaManager,
  lutron: LutronIntegrationManager,
  logStore: LogStore,
  logSampler: LogSamplerHandle
) {
  const r = Router();

  /** Publiek: laat zien of KNX/media bereikbaar zijn (geen auth). */
  /** Public: running version + optional newer GitHub release/tag. */
  r.get("/version", async (req, res) => {
    const force = req.query.refresh === "1" || req.query.refresh === "true";
    const latest = await getGithubLatest(force);
    const updateAvailable = isUpdateAvailableOnGithub(latest);
    const serverUpdate = readServerUpdateStatus();
    res.json({
      version: appVersionInfo.version,
      semver: appVersionInfo.semver,
      build: appVersionInfo.build,
      githubRepo: process.env.GITHUB_REPO?.trim() || "Archie-Automation/visualisatie",
      latest: latest
        ? {
            version: latest.version,
            semver: latest.semver,
            build: latest.build,
            tag: latest.tag,
            htmlUrl: latest.htmlUrl,
            source: latest.source,
            checkedAt: latest.checkedAt,
            androidApk: latest.androidApk
              ? {
                  available: true,
                  name: latest.androidApk.name,
                  sizeBytes: latest.androidApk.sizeBytes,
                  downloadPath: "/api/app/android.apk"
                }
              : null
          }
        : null,
      updateAvailable,
      serverUpdate: {
        agentReady: serverUpdate.agentReady,
        state: serverUpdate.state,
        message: serverUpdate.message
      }
    });
  });

  /**
   * Public: stream the latest Android APK from the GitHub Release asset.
   * Uses GITHUB_TOKEN on the server so tablets never need a GitHub credential.
   */
  r.get("/app/android.apk", async (req, res) => {
    const force = req.query.refresh === "1" || req.query.refresh === "true";
    if (force) await getGithubLatest(true);
    const result = await fetchAndroidApkFromGithub();
    if (!result.ok) {
      res.status(result.status).json({ error: result.error });
      return;
    }
    res.setHeader(
      "Content-Type",
      "application/vnd.android.package-archive"
    );
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="${result.name.replace(/"/g, "")}"`
    );
    if (result.sizeBytes > 0) {
      res.setHeader("Content-Length", String(result.sizeBytes));
    }
    Readable.fromWeb(result.body).pipe(res);
  });

  r.get("/health", (_req, res) => {
    const connectivity = getConnectivitySnapshot(bus, media, lutron);
    const warnings: string[] = [];
    if (!connectivity.knx.disabled && !connectivity.knx.simulate && !connectivity.knx.connected) {
      warnings.push(
        `KNX not connected to ${connectivity.knx.host}:${connectivity.knx.port}`
      );
    }
    for (const m of connectivity.media) {
      if (!m.online) {
        warnings.push(`Media offline: ${m.brand} (${m.name})`);
      }
    }
    for (const l of connectivity.lutron) {
      if (!l.connected) {
        warnings.push(`Lutron telnet offline: ${l.name} (${l.host}:${l.port})`);
      }
    }
    res.json({
      ok: true,
      warnings,
      connectivity
    });
  });

  /** Proxy for Sonos/Spotify album art — no auth (Image.network sends no JWT). */
  r.get("/media-art", async (req, res) => {
    const u = req.query["u"];
    if (typeof u !== "string" || !u.startsWith("http")) {
      return res.status(400).send("bad url");
    }
    try {
      const upstream = await fetch(u, {
        signal: AbortSignal.timeout(4000),
        headers: { "User-Agent": "Linux UPnP/1.0 Sonos/80.0-00000" }
      });
      if (!upstream.ok) {
        return res.status(404).send("not found");
      }
      const ct = upstream.headers.get("content-type") ?? "";
      const buf = await upstream.arrayBuffer();
      if (buf.byteLength === 0 || buf.byteLength > 2_000_000) {
        return res.status(404).send("no image");
      }
      const sniffed = sniffImageContentType(buf, ct);
      if (!sniffed) {
        return res.status(404).send("no image");
      }
      res.setHeader("Content-Type", sniffed);
      const isSonosGetaa = /\/getaa(?:\?|$)/i.test(u);
      res.setHeader(
        "Cache-Control",
        isSonosGetaa ? "no-cache" : "public, max-age=3600"
      );
      res.send(Buffer.from(buf));
    } catch {
      res.status(502).send("upstream error");
    }
  });

  // ── Satel integration config (enabled + partitions) ─────────────────────
  // GET  /api/satel-config  → { enabled: bool, partitions: [{number, name}[]] }
  // POST /api/satel-config  → body { enabled?, partitions? }, responds 204
  r.get("/satel-config", requireAuth, (req: AuthedRequest, res) => {
    const cfg = getConfig();
    const enabled = cfg.satel?.enabled ?? false;
    const u = currentUser(req);
    const allowed =
      isStaffRole(req.user?.role) ||
      isStaffRole(u?.role) ||
      houseFunctionAllowed(u?.access, "alarm");
    res.json({
      enabled: Boolean(enabled && allowed),
      partitions: allowed ? (cfg.satel?.partitions ?? []) : []
    });
  });

  r.post("/satel-config", requireAuth, requireAdmin, (req: AuthedRequest, res) => {
    const { enabled, partitions } = req.body ?? {};
    updateConfig((draft) => {
      draft.satel = draft.satel ?? {};
      if (enabled !== undefined) draft.satel.enabled = Boolean(enabled);
      if (Array.isArray(partitions)) {
        draft.satel.partitions = (partitions as Array<{ number: unknown; name: unknown }>)
          .filter((p) => typeof p.number === "number" && typeof p.name === "string")
          .map((p) => ({ number: p.number as number, name: p.name as string }));
      }
    });
    return res.status(204).end();
  });

  r.post("/auth/login", async (req, res) => {
    const { username, password } = req.body ?? {};
    if (!username || !password)
      return res.status(400).json({ error: "username & password required" });
    const result = await authenticate(username, password);
    if (!result) return res.status(401).json({ error: "invalid credentials" });
    res.json(result);
  });

  r.get("/users", requireAuth, requireStaff, (_req, res) => {
    const users = (getConfig().users ?? []).map((u) =>
      stripHash({
        ...u,
        role: normalizeRole(u.role),
        enabled: u.enabled !== false
      })
    );
    res.json({ users });
  });

  r.put("/users", requireAuth, requireStaff, async (req: AuthedRequest, res) => {
    const actor = currentUser(req);
    if (!actor) return res.status(403).json({ error: "onbekende gebruiker" });

    const StarOrIds = z.union([z.literal("*"), z.array(z.string())]);
    const parsed = z
      .object({
        users: z.array(
          z.object({
            id: z.string().min(1),
            username: z.string().min(1),
            displayName: z.string().optional(),
            role: z.enum(["installer", "superuser", "user", "admin"]),
            passwordHash: z.string().optional(),
            password: z.string().optional(),
            enabled: z.boolean().optional(),
            access: z
              .object({
                floors: StarOrIds.optional(),
                rooms: StarOrIds.optional(),
                functions: StarOrIds.optional(),
                roomFunctions: z.record(StarOrIds).optional(),
                canRelease: StarOrIds.optional(),
                talkIntercoms: StarOrIds.optional(),
                editScenes: z.boolean().optional()
              })
              .optional()
          })
        )
      })
      .safeParse(req.body);
    if (!parsed.success) {
      return res
        .status(400)
        .json({ error: "ongeldige gebruikerslijst", details: parsed.error.issues });
    }

    const body = { users: parsed.data.users as unknown as User[] };
    await applyPlaintextPasswords(body);

    const previous = getConfig();
    const nextUsers = body.users.map((u) =>
      canonicalizeStoredUser({
        ...u,
        passwordHash: u.passwordHash ?? ""
      })
    );
    const draft = structuredClone(previous);
    draft.users = nextUsers;
    mergePasswordHashes(draft, previous);
    const userErr = assertUsersHaveHashes(draft);
    if (userErr) return res.status(400).json({ error: userErr });

    const mutErr = assertUsersMutation(
      actor,
      previous.users ?? [],
      draft.users ?? []
    );
    if (mutErr) return res.status(403).json({ error: mutErr });

    persistConfig(draft);
    ws.broadcastConfigChanged(getConfigVersion());
    const users = (getConfig().users ?? []).map((u) =>
      stripHash({
        ...u,
        role: normalizeRole(u.role),
        enabled: u.enabled !== false
      })
    );
    res.json({ ok: true, users });
  });

  r.get("/config", requireAuth, (req: AuthedRequest, res) => {
    const cfg = getConfig();
    res.json(publicConfig(cfg, req.user!.role, req.user!.sub));
  });

  r.post("/config/reload", requireAuth, requireAdmin, async (_req, res) => {
    const cfg = loadConfig();
    syncGo2rtcProcessAfterConfigWritten(writeGo2rtcConfig(cfg));
    scheduler.reschedule();
    logSampler.refresh();
    media.rebuild(cfg);
    lutron.rebuild(cfg);
    try {
      await bus.refreshGroupAddresses(collectAllGAs(cfg));
    } catch (err) {
      logger.warn({ err }, "KNX GA refresh after reload failed");
    }
    ws.broadcastConfigChanged(getConfigVersion());
    res.json({
      ok: true,
      floors: cfg.floors.length,
      version: getConfigVersion()
    });
  });

  /** Herstart backend: Docker via container-restart; lokaal via nieuw proces. */
  r.post("/admin/restart", requireAuth, requireAdmin, (req: AuthedRequest, res) => {
    logger.warn({ userId: req.user?.sub }, "admin requested backend restart");
    res.status(200).json({
      ok: true,
      message: "Backend wordt opnieuw opgestart."
    });
    res.on("finish", () => {
      scheduleAdminProcessRestart();
    });
  });

  r.get("/admin/update", requireAuth, requireAdmin, (_req, res) => {
    res.json(readServerUpdateStatus());
  });

  r.post("/admin/update", requireAuth, requireAdmin, (req: AuthedRequest, res) => {
    const result = requestServerUpdate(req.user?.username || "admin");
    if (!result.ok) {
      res.status(result.status).json({
        error: result.error,
        message: result.message
      });
      return;
    }
    res.json({ ok: true, ...result.status });
  });

  r.get("/installer/house", requireAuth, requireAdmin, (_req, res) => {
    res.json(installerHouseForClient(getConfig()));
  });

  r.put("/installer/house", requireAuth, requireAdmin, async (req, res) => {
    await applyPlaintextPasswords(req.body);
    normalizeHouseCamerasRaw(req.body);
    normalizeHouseIntercomsRaw(req.body);
    const parsed = validateHouseJson(req.body);
    if (!parsed.ok) {
      return res
        .status(400)
        .json({ error: "validation failed", issues: parsed.errors });
    }
    const next = parsed.data;
    mergePasswordHashes(next, getConfig());
    mergeLutronTelnetPasswords(next, getConfig());
    const userErr = assertUsersHaveHashes(next);
    if (userErr) return res.status(400).json({ error: userErr });
    const fpIssues = validateFireplaceSemantics(next);
    if (fpIssues.length > 0) {
      return res.status(400).json({ error: "validation failed", issues: fpIssues });
    }
    const icIssues = validateIntercomSemantics(next);
    if (icIssues.length > 0) {
      return res.status(400).json({ error: "validation failed", issues: icIssues });
    }
    const rgbIssues = validateRgbwWwSemantics(next);
    if (rgbIssues.length > 0) {
      return res.status(400).json({ error: "validation failed", issues: rgbIssues });
    }
    const lutronIssues = validateLutronSemantics(next);
    if (lutronIssues.length > 0) {
      return res.status(400).json({ error: "validation failed", issues: lutronIssues });
    }
    const lutronLoadIssues = validateLutronLoadOutputSemantics(next);
    if (lutronLoadIssues.length > 0) {
      return res.status(400).json({ error: "validation failed", issues: lutronLoadIssues });
    }
    persistConfig(next);
    syncGo2rtcProcessAfterConfigWritten(writeGo2rtcConfig(getConfig()));
    scheduler.reschedule();
    logSampler.refresh();
    media.rebuild(getConfig());
    lutron.rebuild(getConfig());
    try {
      await bus.refreshGroupAddresses(collectAllGAs(getConfig()));
    } catch (err) {
      logger.warn({ err }, "KNX GA refresh after installer save failed");
    }
    const version = getConfigVersion();
    ws.broadcastConfigChanged(version);
    res.json({ ok: true, version });
  });

  r.get("/installer/knx-status", requireAuth, requireAdmin, (_req, res) => {
    res.json(bus.getStatus());
  });

  /**
   * Parse a KNX Group Address XML (ETS export or Archie Groepsadressentool).
   * Returns a preview: a proposal of hoofdfunctie-devices per floor/room plus
   * the full searchable GA catalog. Persists the catalog immediately (harmless
   * reference data) but does NOT touch house.json — the installer confirms the
   * device proposal in the UI, which then merges + saves via PUT /installer/house.
   */
  r.post("/installer/import-knx", requireAuth, requireAdmin, (req, res) => {
    const xml =
      typeof req.body === "string"
        ? req.body
        : typeof req.body?.xml === "string"
          ? (req.body.xml as string)
          : "";
    if (!xml.trim()) {
      return res.status(400).json({ error: "geen XML ontvangen" });
    }
    try {
      const result = parseKnxExport(xml);
      if (result.catalog.length === 0) {
        return res
          .status(400)
          .json({ error: "geen groepsadressen gevonden in dit bestand" });
      }
      persistGaCatalog(result.catalog);
      logger.info(
        {
          addresses: result.stats.addresses,
          devices: result.stats.devices,
          floors: result.stats.floors,
          rooms: result.stats.rooms,
        },
        "KNX XML import parsed"
      );
      res.json(result);
    } catch (err) {
      logger.warn({ err }, "KNX XML import failed");
      res.status(400).json({
        error: err instanceof Error ? err.message : "import mislukt",
      });
    }
  });

  /** Searchable GA catalog for the installer GA fields (name + address + DPT). */
  r.get("/installer/knx-ga", requireAuth, requireAdmin, (_req, res) => {
    res.json({ catalog: loadGaCatalog() });
  });

  r.get("/installer/lutron-status", requireAuth, requireAdmin, (_req, res) => {
    const clients = lutron.getStatus();
    const row = clients.find((c) => c.deviceId === "house") ?? clients[0];
    if (!row) {
      return res.json({
        connected: false,
        loggedIn: false,
        host: "",
        port: 23,
        clients: []
      });
    }
    res.json({
      connected: row.connected,
      loggedIn: row.loggedIn,
      host: row.host,
      port: row.port,
      lastError: row.lastError,
      clients
    });
  });

  r.post("/installer/lutron-reconnect", requireAuth, requireAdmin, (_req, res) => {
    try {
      lutron.reconnect();
      const clients = lutron.getStatus();
      const row = clients.find((c) => c.deviceId === "house") ?? clients[0];
      res.json({
        ok: true,
        connected: row?.connected ?? false,
        loggedIn: row?.loggedIn ?? false,
        host: row?.host ?? "",
        port: row?.port ?? 23,
        clients
      });
    } catch (err) {
      logger.warn({ err }, "Lutron manual reconnect failed");
      res.status(500).json({
        error: err instanceof Error ? err.message : "reconnect failed",
        clients: lutron.getStatus()
      });
    }
  });

  r.post("/installer/knx-reconnect", requireAuth, requireAdmin, async (_req, res) => {
    try {
      await bus.reconnect();
      res.json({ ok: true, ...bus.getStatus() });
    } catch (err) {
      logger.warn({ err }, "KNX manual reconnect failed");
      res.status(500).json({
        error: err instanceof Error ? err.message : "reconnect failed",
        ...bus.getStatus()
      });
    }
  });

  r.post("/installer/sonos-probe", requireAuth, requireAdmin, async (req, res) => {
    const host = req.body?.host as string | undefined;
    const portRaw = req.body?.port;
    const port =
      portRaw === undefined || portRaw === ""
        ? 1400
        : Number(portRaw);
    const p = Number.isFinite(port) ? Math.trunc(port) : 1400;
    const result = await probeSonos(host ?? "", p);
    res.json(result);
  });

  r.post("/installer/camera-probe", requireAuth, requireAdmin, async (req, res) => {
    const result = await probeCameraStreams({
      rtsp: req.body?.rtsp as string | undefined,
      previewRtsp: req.body?.previewRtsp as string | undefined,
      codec: req.body?.codec as string | undefined
    });
    res.json(result);
  });

  /* ----------------------------- Media bases ------------------------- */

  const mediaBase = () =>
    (process.env.MEDIA_BASE_URL ?? "http://localhost:1984").replace(/\/+$/, "");
  const apiBase = () =>
    (process.env.PUBLIC_API_BASE ?? "").replace(/\/+$/, "");
  const clientApiBase = (req: import("express").Request) => {
    const env = apiBase();
    if (env) return env;
    const proto = (req.get("x-forwarded-proto") ?? req.protocol ?? "http")
      .split(",")[0]
      ?.trim();
    const host = (req.get("x-forwarded-host") ?? req.get("host") ?? "localhost:4000")
      .split(",")[0]
      ?.trim();
    return `${proto}://${host}`;
  };

  /* ------------------------------ Cameras ---------------------------- */
  // Cameras are view-only. No microphone, no backchannel. Period.

  r.get("/cameras", requireAuth, (req, res) => {
    const cams = collectCameras(getConfig());
    const base = clientApiBase(req);
    res.json({ cameras: cams.map((c) => publicCamera(c, mediaBase(), base)) });
  });

  r.get("/cameras/:id", requireAuth, (req, res) => {
    const cam = collectCameras(getConfig()).find((c) => c.id === req.params.id);
    if (!cam) return res.status(404).json({ error: "unknown camera" });
    res.json(publicCamera(cam, mediaBase(), clientApiBase(req)));
  });

  r.get("/cameras/:id/snapshot", requireAuth, (req, res) =>
    proxySnapshot(req, res, "camera", mediaBase())
  );

  r.post("/cameras/:id/warm", requireAuth, async (req, res) => {
    const cam = collectCameras(getConfig()).find((c) => c.id === req.params.id);
    if (!cam) return res.status(404).json({ error: "unknown camera" });
    const warmed = await warmGo2rtcProducer(mediaBase(), cameraPath(cam), {
      retries: 4,
      timeoutMs: 22_000
    });
    return res.json({ warmed });
  });

  r.get("/cameras/:id/hls.m3u8", requireAuth, async (req, res) => {
    const cam = collectCameras(getConfig()).find((c) => c.id === req.params.id);
    if (!cam) return res.status(404).end();
    if (cam.camera.directHls) {
      return res.redirect(cam.camera.directHls);
    }
    const p = cameraPath(cam);
    const url = `${mediaBase()}/api/stream.m3u8?src=${encodeURIComponent(p)}`;
    try {
      const upstream = await fetch(url, {
        signal: AbortSignal.timeout(25_000)
      });
      if (!upstream.ok) return res.status(upstream.status).end();
      const body = rewriteHlsPlaylist(
        await upstream.text(),
        cam.id,
        clientApiBase(req),
        mediaBase()
      );
      res.setHeader("content-type", "application/vnd.apple.mpegurl");
      res.setHeader("cache-control", "no-cache");
      return res.send(body);
    } catch (err) {
      logger.warn({ err, id: cam.id }, "hls manifest proxy failed");
      return res.status(502).json({ error: "hls unavailable" });
    }
  });

  // Must be a path-scoped route. `r.use(requireAuth, …)` without a prefix
  // also wraps every later route — including unauthenticated Spotify
  // `/tls-ok` and `/callback`, which then return `{ error: "missing token" }`.
  r.get("/cameras/:id/hls-seg/*", requireAuth, async (req, res) => {
    const cam = collectCameras(getConfig()).find((c) => c.id === req.params.id);
    if (!cam) return res.status(404).end();
    const rest = typeof req.params[0] === "string" ? req.params[0] : "";
    if (!rest) return res.status(404).end();
    const upstreamUrl = `${mediaBase()}/api/${rest}`;
    try {
      await proxyHlsBody(res, upstreamUrl);
    } catch (err) {
      logger.warn({ err, id: cam.id, path: rest }, "hls segment proxy failed");
      res.status(502).json({ error: "hls segment unavailable" });
    }
  });

  r.post("/cameras/:id/webrtc", requireAuth, async (req, res) => {
    const cam = collectCameras(getConfig()).find((c) => c.id === req.params.id);
    if (!cam) return res.status(404).json({ error: "unknown camera" });
    // Strip any sendonly/sendrecv audio from the offer just in case a
    // modified client tries to push mic audio through the camera path.
    const offer = req.body as { type: string; sdp: string };
    if (!offer?.sdp || !offer?.type)
      return res.status(400).json({ error: "bad offer" });
    if (/a=sendrecv|a=sendonly/.test(offer.sdp) && /m=audio/.test(offer.sdp)) {
      logger.warn(
        { id: cam.id },
        "client tried to enable mic on a camera – rejecting"
      );
      return res.status(403).json({ error: "microphone not allowed on cameras" });
    }
    await forwardSignalling(req, res, cameraPath(cam), mediaBase());
  });

  /* ----------------------------- Intercoms --------------------------- */
  // Intercoms = WebRTC + talk + door release + ring event.

  r.get("/intercoms", requireAuth, (req: AuthedRequest, res) => {
    const list = collectIntercoms(getConfig()).filter((i) =>
      canViewIntercom(req, i.id)
    );
    const base = clientApiBase(req);
    res.json({
      intercoms: list.map((c) => ({
        ...publicIntercom(c, mediaBase(), base),
        canRelease: canReleaseIntercom(req, c.id)
      }))
    });
  });

  r.get("/intercoms/:id", requireAuth, (req: AuthedRequest, res) => {
    if (!canViewIntercom(req, req.params.id))
      return res.status(403).json({ error: "not allowed" });
    const ic = collectIntercoms(getConfig()).find((i) => i.id === req.params.id);
    if (!ic) return res.status(404).json({ error: "unknown intercom" });
    res.json({
      ...publicIntercom(ic, mediaBase(), clientApiBase(req)),
      canRelease: canReleaseIntercom(req, ic.id)
    });
  });

  r.get("/intercoms/:id/snapshot", requireAuth, (req: AuthedRequest, res) => {
    if (!canViewIntercom(req, req.params.id))
      return res.status(403).end();
    return proxySnapshot(req, res, "intercom", mediaBase());
  });

  r.post("/intercoms/:id/webrtc", requireAuth, async (req: AuthedRequest, res) => {
    if (!canViewIntercom(req, req.params.id))
      return res.status(403).json({ error: "not allowed" });
    const ic = collectIntercoms(getConfig()).find(
      (i) => i.id === req.params.id
    );
    if (!ic) return res.status(404).json({ error: "unknown intercom" });
    // Talk-back is intentional here. No SDP filtering.
    await forwardSignalling(req, res, cameraPath(ic), mediaBase());
  });

  /**
   * Geeft de volledige SIP-configuratie terug (inclusief wachtwoord) zodat de
   * app bij opstart kan registreren. Alleen voor geauthenticeerde gebruikers
   * die toegang hebben tot dit intercom.
   */
  r.get("/intercoms/:id/sip", requireAuth, (req: AuthedRequest, res) => {
    if (!canViewIntercom(req, req.params.id))
      return res.status(403).json({ error: "not allowed" });
    const ic = collectIntercoms(getConfig()).find((i) => i.id === req.params.id);
    if (!ic) return res.status(404).json({ error: "unknown intercom" });
    if (!ic.intercom.sip || ic.intercom.kind !== "sip")
      return res.status(404).json({ error: "no SIP config for this intercom" });
    res.json({ sip: ic.intercom.sip });
  });

  /**
   * HTTP ring-webhook voor DoorBird / 2N / andere intercomsystemen.
   * Geen JWT vereist (DoorBird kan geen Bearer-token meesturen).
   * Beveiliging via optionele `passcode` query-parameter.
   *
   * DoorBird-configuratie (Schedule → HTTP(S) call):
   *   URL: http://<server>:4000/api/webhooks/ring/<intercomId>?passcode=<code>
   *   Method: GET of POST
   *
   * 2N Helios-configuratie (HTTP API Automation):
   *   Hetzelfde URL-formaat; gebruik POST.
   */
  const webhookRingHandler = (req: import("express").Request, res: import("express").Response) => {
    const ic = collectIntercoms(getConfig()).find((i) => i.id === req.params.id);
    if (!ic) return res.status(404).json({ error: "unknown intercom" });

    const expected = (ic.intercom.webhookPasscode ?? "").trim();
    const provided = (
      (req.query.passcode as string | undefined) ??
      req.body?.passcode ??
      ""
    ).trim();

    if (expected.length > 0 && provided !== expected) {
      logger.warn({ id: ic.id, ip: req.ip }, "ring-webhook: ongeldige passcode");
      return res.status(403).json({ error: "invalid passcode" });
    }

    ws.broadcastIntercomRing(ic.id);
    logger.info({ id: ic.id, ip: req.ip, kind: ic.intercom.kind ?? "generic" },
      "ring-webhook: bel ontvangen");
    res.json({ ok: true, id: ic.id });
  };

  r.get("/webhooks/ring/:id", webhookRingHandler);
  r.post("/webhooks/ring/:id", webhookRingHandler);

  r.post("/intercoms/:id/release", requireAuth, async (req: AuthedRequest, res) => {
    if (!canReleaseIntercom(req, req.params.id)) {
      logger.warn(
        { user: req.user?.username, id: req.params.id },
        "door release denied by ACL"
      );
      return res
        .status(403)
        .json({ error: "not allowed to open this door" });
    }
    const ic = collectIntercoms(getConfig()).find(
      (i) => i.id === req.params.id
    );
    if (!ic) return res.status(404).json({ error: "unknown intercom" });
    try {
      await releaseDoor(ic, bus);
      logger.info(
        { user: req.user?.username, id: ic.id },
        "door released"
      );
      res.json({ ok: true });
    } catch (err) {
      logger.warn({ err, id: ic.id }, "door release failed");
      res.status(400).json({ error: (err as Error).message });
    }
  });

  /* ------------------------------ Scenes ----------------------------- */
  // A scene is a list of KNX writes. Stored in house.json, editable by
  // any authenticated user (unless their ACL explicitly forbids it).

  const SceneActionSchema = z
    .object({
      ga: z.string().regex(/^\d+\/\d+\/\d+$/),
      role: z.enum([
        "switch",
        "dim_value",
        "setpoint",
        "position",
        "scene_number",
        "bit",
        "byte",
        "percent",
        "temperature",
        "raw_bytes",
        "rgb232",
        "pulse"
      ]),
      value: z.union([
        z.boolean(),
        z.number(),
        z.array(z.number().int().min(0).max(255)),
        z.object({
          red: z.number(),
          green: z.number(),
          blue: z.number()
        })
      ]),
      delayMs: z.number().int().min(0).max(30_000).optional(),
      pulseMs: z.number().int().min(50).max(3000).optional()
    })
    .superRefine((data, ctx) => {
      if (data.role === "pulse") {
        return;
      }
      if (data.role === "raw_bytes") {
        if (!Array.isArray(data.value)) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "raw_bytes requires value as number[]",
            path: ["value"]
          });
        }
        return;
      }
      if (data.role === "rgb232") {
        const okArr = Array.isArray(data.value) && data.value.length >= 3;
        const okObj =
          typeof data.value === "object" &&
          data.value !== null &&
          !Array.isArray(data.value) &&
          "red" in data.value &&
          "green" in data.value &&
          "blue" in data.value;
        if (!okArr && !okObj) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "rgb232 requires [r,g,b] or {red,green,blue}",
            path: ["value"]
          });
        }
        return;
      }
      if (Array.isArray(data.value) || (typeof data.value === "object" && data.value !== null)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "value must be boolean or number for this role",
          path: ["value"]
        });
      }
    });

  const SceneMediaActionSchema = z.discriminatedUnion("kind", [
    z.object({
      deviceId: z.string().min(1).max(64),
      kind: z.literal("transport"),
      action: z.enum(["play", "pause", "stop", "next", "previous"]),
      delayMs: z.number().int().min(0).max(30_000).optional()
    }),
    z.object({
      deviceId: z.string().min(1).max(64),
      kind: z.literal("volume"),
      value: z.number().min(0).max(100),
      delayMs: z.number().int().min(0).max(30_000).optional()
    }),
    z.object({
      deviceId: z.string().min(1).max(64),
      kind: z.literal("mute"),
      muted: z.boolean(),
      delayMs: z.number().int().min(0).max(30_000).optional()
    }),
    z.object({
      deviceId: z.string().min(1).max(64),
      kind: z.literal("preset"),
      presetId: z.string().min(1).max(120),
      presetName: z.string().max(120).optional(),
      uri: z.string().max(512).optional(),
      delayMs: z.number().int().min(0).max(30_000).optional()
    })
  ]);

  const SceneSchema = z.object({
    id: z.string().min(1).max(64),
    name: z.string().min(1).max(60),
    icon: z.string().max(40).optional(),
    color: z.string().max(10).optional(),
    actions: z.array(SceneActionSchema).max(64),
    mediaActions: z.array(SceneMediaActionSchema).max(16).optional()
  });

  r.post("/scenes/:id/run", requireAuth, async (req: AuthedRequest, res) => {
    const cfg = getConfig();
    const hit = findScene(cfg, req.params.id);
    if (!hit) return res.status(404).json({ error: "unknown scene" });
    // Room-scoped scenes honour the user's room ACL.
    if (hit.scope === "room" && hit.roomId) {
      const scrubbed = publicConfig(cfg, req.user!.role, req.user!.sub);
      const stillVisible = scrubbed.floors.some((f) =>
        f.rooms.some((r) => r.id === hit.roomId)
      );
      if (!stillVisible)
        return res.status(403).json({ error: "room not allowed" });
    }
    try {
      await runScene(hit.scene, bus, cfg, media);
      res.json({ ok: true, sceneId: hit.scene.id });
    } catch (err) {
      logger.warn({ err, id: hit.scene.id }, "scene run failed");
      res.status(500).json({ error: (err as Error).message });
    }
  });

  r.put("/scenes", requireAuth, (req: AuthedRequest, res) => {
    if (!canEditScenes(req))
      return res.status(403).json({ error: "scene editing not allowed" });
    const parsed = z.object({ scenes: z.array(SceneSchema).max(32) }).safeParse(req.body);
    if (!parsed.success)
      return res.status(400).json({ error: "bad scenes", issues: parsed.error.issues });
    updateConfig((draft) => {
      draft.scenes = parsed.data.scenes as Scene[];
    });
    res.json({ ok: true, count: parsed.data.scenes.length });
  });

  r.put("/rooms/:roomId/scenes", requireAuth, (req: AuthedRequest, res) => {
    if (!canEditScenes(req))
      return res.status(403).json({ error: "scene editing not allowed" });
    const room = findRoom(getConfig(), req.params.roomId);
    if (!room) return res.status(404).json({ error: "unknown room" });

    // Enforce room-level ACL so a user can only edit rooms they can see.
    const scrubbed = publicConfig(getConfig(), req.user!.role, req.user!.sub);
    const visible = scrubbed.floors.some((f) =>
      f.rooms.some((r) => r.id === room.id)
    );
    if (!visible) return res.status(403).json({ error: "room not allowed" });

    const parsed = z
      .object({ scenes: z.array(SceneSchema).max(8) })
      .safeParse(req.body);
    if (!parsed.success)
      return res.status(400).json({ error: "bad scenes", issues: parsed.error.issues });

    updateConfig((draft) => {
      for (const f of draft.floors) {
        for (const r of f.rooms) {
          if (r.id === room.id) r.scenes = parsed.data.scenes as Scene[];
        }
      }
    });
    res.json({ ok: true, count: parsed.data.scenes.length });
  });

  /* ---------------------------- Schedules ---------------------------- */
  // Time / astro schedules. Any authed user can see & toggle their own,
  // but mutating the config requires the scene-edit permission (same
  // privilege model — customers manage their own automations).

  const HHMM = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
  const WeekdayMaskSchema = z
    .array(z.boolean())
    .length(7) as unknown as z.ZodType<[
      boolean, boolean, boolean, boolean, boolean, boolean, boolean
    ]>;

  const GuardSchema = z.discriminatedUnion("kind", [
    z.object({ kind: z.literal("time"), time: z.string().regex(HHMM) }),
    z.object({
      kind: z.literal("astro"),
      event: z.enum(["sunrise", "sunset"]),
      offsetMin: z.number().int().min(-720).max(720).optional()
    })
  ]);

  const TriggerSchema = z.discriminatedUnion("kind", [
    z.object({
      kind: z.literal("time"),
      time: z.string().regex(HHMM),
      days: WeekdayMaskSchema
    }),
    z.object({
      kind: z.literal("astro"),
      event: z.enum(["sunrise", "sunset"]),
      offsetMin: z.number().int().min(-720).max(720).optional(),
      days: WeekdayMaskSchema,
      notBefore: GuardSchema.optional(),
      notAfter: GuardSchema.optional()
    })
  ]);

  const ActionSchema = z.discriminatedUnion("kind", [
    z.object({
      kind: z.literal("scene"),
      sceneId: z.string().min(1).max(64),
      steps: z
        .array(
          z.object({
            sceneId: z.string().min(1).max(64),
            delayMs: z.number().int().min(0).max(1_800_000).optional()
          })
        )
        .min(1)
        .max(32)
        .optional()
    }),
    z.object({
      kind: z.literal("actions"),
      actions: z.array(SceneActionSchema).min(1).max(64)
    })
  ]);

  const ConditionSchema = z.discriminatedUnion("kind", [
    z.object({
      kind: z.literal("device"),
      deviceId: z.string().min(1).max(64),
      actions: z.array(SceneActionSchema).min(1).max(8)
    }),
    z.object({
      kind: z.literal("logic"),
      deviceId: z.string().min(1).max(64),
      buttonId: z.string().min(1).max(64),
      equals: z.boolean()
    })
  ]);

  const ScheduleSchema = z.object({
    id: z.string().min(1).max(64),
    name: z.string().min(1).max(60),
    enabled: z.boolean(),
    trigger: TriggerSchema,
    action: ActionSchema,
    conditions: z.array(ConditionSchema).max(16).optional(),
    lastRun: z.string().datetime().optional()
  });

  r.get("/schedules", requireAuth, (_req, res) => {
    res.json({ schedules: getConfig().schedules ?? [] });
  });

  r.put("/schedules", requireAuth, (req: AuthedRequest, res) => {
    if (!canEditScenes(req))
      return res.status(403).json({ error: "schedule editing not allowed" });
    const parsed = z
      .object({ schedules: z.array(ScheduleSchema).max(64) })
      .safeParse(req.body);
    if (!parsed.success)
      return res
        .status(400)
        .json({ error: "bad schedules", issues: parsed.error.issues });
    updateConfig((draft) => {
      draft.schedules = parsed.data.schedules as Schedule[];
    });
    scheduler.reschedule();
    res.json({ ok: true, count: parsed.data.schedules.length });
  });

  r.post(
    "/schedules/:id/run",
    requireAuth,
    async (req: AuthedRequest, res) => {
      if (!canEditScenes(req))
        return res.status(403).json({ error: "not allowed" });
      try {
        await scheduler.runNow(req.params.id);
        res.json({ ok: true });
      } catch (err) {
        res.status(400).json({ error: (err as Error).message });
      }
    }
  );

  /* ------------------------------ Debug ------------------------------ */
  // Admin-only. Synthesises a doorbell ring for local testing without
  // needing the physical button. Only enabled outside production.

  if (process.env.NODE_ENV !== "production") {
    r.post(
      "/debug/ring/:id",
      requireAuth,
      requireAdmin,
      (req: AuthedRequest, res) => {
        const ic = collectIntercoms(getConfig()).find(
          (i) => i.id === req.params.id
        );
        if (!ic) return res.status(404).json({ error: "unknown intercom" });
        ws.broadcastIntercomRing(ic.id);
        logger.info(
          { by: req.user?.username, id: ic.id },
          "synthetic ring fired"
        );
        res.json({ ok: true, id: ic.id, name: ic.name });
      }
    );
  }

  /* ------------------------------ State ------------------------------ */

  r.get("/state", requireAuth, (_req, res) => {
    res.json({
      states: bus.getAll(),
      hvacLocks: hvacSwitchLock.getAll(),
      fireplaceVirtual: fireplaceVirtual.getAll()
    });
  });

  r.get("/state/:ga", requireAuth, (req, res) => {
    const s = bus.getState(req.params.ga);
    if (!s) return res.status(404).json({ error: "unknown GA" });
    res.json(s);
  });

  // ── Logs / grafieken ──────────────────────────────────────────────────
  // List available logs (one per thermostat + installer-defined custom logs).
  r.get("/logs", requireAuth, (_req, res) => {
    res.json({ logs: listLogDefs(getConfig()) });
  });

  // Historical, downsampled series for a single log within [from, to].
  r.get("/logs/:id/history", requireAuth, (req, res) => {
    const def = findLogDef(getConfig(), req.params.id);
    if (!def) return res.status(404).json({ error: "unknown log" });

    const now = Date.now();
    const to = parseTs(req.query.to, now);
    const from = parseTs(req.query.from, now - 24 * 60 * 60 * 1000);
    const maxPoints = parseIntRange(req.query.maxPoints, 500, 50, 2000);
    if (from >= to) {
      return res.status(400).json({ error: "from must be before to" });
    }

    const gas = [...new Set(def.series.map((s) => s.ga))];
    const data = logStore.query(gas, from, to, maxPoints);
    res.json({
      id: def.id,
      name: def.name,
      kind: def.kind,
      from,
      to,
      series: def.series.map((s) => ({
        ga: s.ga,
        label: s.label,
        unit: s.unit ?? null,
        role: s.role ?? null,
        points: (data[s.ga] ?? []).map((p) => [p.ts, p.value])
      }))
    });
  });

  r.post("/command", requireAuth, async (req: AuthedRequest, res) => {
    const parsed = CommandSchema.safeParse(req.body);
    if (!parsed.success) {
      return res
        .status(400)
        .json({ error: "invalid command", details: parsed.error.issues });
    }
    const deviceId =
      "deviceId" in parsed.data ? parsed.data.deviceId : undefined;
    if (typeof deviceId === "string") {
      const u = currentUser(req);
      if (!userMayUseDevice(u, req.user?.role, getConfig(), deviceId)) {
        return res.status(403).json({ error: "geen toegang tot dit apparaat" });
      }
    }
    try {
      await dispatch(parsed.data, getConfig(), bus, media, lutron);
      res.json({ ok: true });
    } catch (err) {
      logger.warn({ err, cmd: parsed.data }, "command dispatch failed");
      res.status(400).json({ error: (err as Error).message });
    }
  });

  /* ------------------------------- Media ------------------------------- */

  r.get("/media", requireAuth, (_req, res) => {
    res.json({ states: media.getAll() });
  });

  r.get("/media/:id", requireAuth, (req, res) => {
    const s = media.get(req.params.id);
    if (!s) return res.status(404).json({ error: "unknown media device" });
    res.json(s);
  });

  /** Search the services linked on a player (Sonos favourites/library,
   *  Bluesound's linked BluOS services). Body: { deviceId, query }. */
  r.post("/media/search", requireAuth, async (req, res) => {
    const body = req.body as { deviceId?: unknown; query?: unknown };
    const deviceId = typeof body?.deviceId === "string" ? body.deviceId : "";
    const query = typeof body?.query === "string" ? body.query : "";
    if (!deviceId || !query.trim()) {
      return res.status(400).json({ error: "deviceId and query required" });
    }
    try {
      const { sections, needsSpotifyAuth } = await media.search(deviceId, query);
      res.json({ sections, needsSpotifyAuth });
    } catch (err) {
      logger.warn({ err, deviceId }, "media search failed");
      res.status(400).json({ error: (err as Error).message });
    }
  });

  /* ----------------------------- Spotify ------------------------------- */

  /** Best-effort public base URL of this backend, used to derive the Spotify
   *  redirect URI when the installer didn't set one explicitly. */
  const spotifyServerBase = (req: { protocol: string; get(h: string): string | undefined }) => {
    const env = (process.env.PUBLIC_API_BASE ?? "").trim().replace(/\/+$/, "");
    const fromReq = `${req.protocol}://${req.get("host") ?? ""}`.replace(/\/+$/, "");
    if (fromReq && !spotify.isLoopbackUrl(fromReq)) return fromReq;
    if (env && !spotify.isLoopbackUrl(env)) return env;
    return fromReq;
  };

  /** Connection status — the app shows "verbonden als ...", the redirect URI
   *  to paste into the Spotify dashboard, and decides whether to offer search. */
  r.get("/media/spotify/status", requireAuth, (req, res) => {
    const status = spotify.getStatus();
    const suggestedRedirectUri = spotify.resolveRedirectUri(spotifyServerBase(req));
    const tlsCheckUrl = suggestedRedirectUri.startsWith("https:")
      ? suggestedRedirectUri.replace(/\/callback$/, "/tls-ok")
      : undefined;
    res.json({
      ...status,
      suggestedRedirectUri,
      tlsCheckUrl
    });
  });

  /** Save the OAuth app credentials entered in the app (no server restart). */
  r.post("/media/spotify/config", requireAuth, (req, res) => {
    const body = req.body as {
      clientId?: unknown;
      clientSecret?: unknown;
      redirectUri?: unknown;
    };
    const clientId = typeof body?.clientId === "string" ? body.clientId.trim() : "";
    const clientSecret =
      typeof body?.clientSecret === "string" ? body.clientSecret.trim() : "";
    if (!clientId || !clientSecret) {
      return res.status(400).json({ error: "clientId en clientSecret zijn verplicht" });
    }
    const redirectUri = spotify.resolveRedirectUri(spotifyServerBase(req));
    spotify.saveAppCredentials({ clientId, clientSecret, redirectUri });
    res.json(spotify.getStatus());
  });

  /** Returns the Spotify authorize URL for the app to open in a browser.
   *  A short-lived state guards the callback against CSRF. */
  r.get("/media/spotify/login", requireAuth, (req, res) => {
    if (!spotify.isConfigured()) {
      return res.status(400).json({
        error:
          "Spotify is nog niet ingesteld. Vul eerst de Client ID en Secret in."
      });
    }
    const state = randomUUID();
    spotifyAuthStates.add(state);
    // Expire unused states after 10 minutes to avoid unbounded growth.
    setTimeout(() => spotifyAuthStates.delete(state), 10 * 60 * 1000);
    res.json({ url: spotify.buildAuthUrl(state, spotifyServerBase(req)) });
  });

  /** Unauthenticated: open this over HTTPS once so the browser trusts the
   *  self-signed cert before Spotify redirects here. */
  r.get("/media/spotify/tls-ok", (_req, res) => {
    res.type("html").send(`<!doctype html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Spotify</title>
<style>body{font-family:system-ui,sans-serif;background:#121212;color:#fff;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}
.card{max-width:420px;padding:2rem}h1{font-size:1.25rem;margin:0 0 .75rem}
p{color:#b3b3b3;margin:0}</style></head>
<body><div class="card"><h1>Certificaat OK</h1>
<p>Je kunt dit venster sluiten en in de app op Verbind Spotify tikken.</p>
</div></body></html>`);
  });

  /** Spotify redirects the browser here after login. No app auth header is
   *  present (it's a browser redirect), so we rely on the `state` value. */
  r.get("/media/spotify/callback", async (req, res) => {
    const home = httpAppHome(req);
    const usedRedirect = `${req.protocol}://${req.get("host") ?? ""}/api/media/spotify/callback`;
    const code = typeof req.query["code"] === "string" ? req.query["code"] : "";
    const state = typeof req.query["state"] === "string" ? req.query["state"] : "";
    const err = typeof req.query["error"] === "string" ? req.query["error"] : "";
    if (err) {
      return res.status(400).send(spotifyResultPage(`Spotify-login geannuleerd: ${err}`, home));
    }
    if (!code || !state) {
      return res.status(400).send(spotifyResultPage("Ongeldige of verlopen login-poging.", home));
    }
    const nonce = spotify.parseOauthNonce(state);
    if (!spotifyAuthStates.has(nonce)) {
      return res.status(400).send(spotifyResultPage("Ongeldige of verlopen login-poging.", home));
    }
    spotifyAuthStates.delete(nonce);
    try {
      await spotify.exchangeCode(code, usedRedirect);
      res.send(
        spotifyResultPage(
          "Spotify is verbonden. Je wordt teruggestuurd naar de app.",
          home,
          true
        )
      );
    } catch (e) {
      logger.warn({ err: e }, "spotify callback failed");
      res.status(400).send(
        spotifyResultPage("Verbinden met Spotify is mislukt. Probeer het opnieuw.", home)
      );
    }
  });

  /** Finish OAuth when the browser could not reach 127.0.0.1 (LAN install).
   *  The user pastes the callback URL from the address bar. */
  r.post("/media/spotify/finish", requireAuth, async (req, res) => {
    const body = req.body as { url?: unknown; code?: unknown; state?: unknown };
    let code = typeof body?.code === "string" ? body.code.trim() : "";
    let state = typeof body?.state === "string" ? body.state.trim() : "";
    let urlRaw = typeof body?.url === "string" ? body.url.trim() : "";
    if (urlRaw && !/^[a-z][a-z0-9+.-]*:/i.test(urlRaw)) {
      urlRaw = `http://${urlRaw}`;
    }
    if (urlRaw && (!code || !state)) {
      try {
        const u = new URL(urlRaw);
        code = code || u.searchParams.get("code") || "";
        state = state || u.searchParams.get("state") || "";
        const err = u.searchParams.get("error");
        if (err) {
          return res.status(400).json({ error: `Spotify-login geannuleerd: ${err}` });
        }
      } catch {
        return res.status(400).json({ error: "Ongeldige callback-URL" });
      }
    }
    if (!code || !state) {
      return res.status(400).json({ error: "Ongeldige of verlopen login-poging." });
    }
    const nonce = spotify.parseOauthNonce(state);
    if (!spotifyAuthStates.has(nonce)) {
      return res.status(400).json({ error: "Ongeldige of verlopen login-poging." });
    }
    spotifyAuthStates.delete(nonce);
    try {
      await spotify.exchangeCode(code);
      res.json(spotify.getStatus());
    } catch (e) {
      logger.warn({ err: e }, "spotify finish failed");
      res.status(400).json({ error: "Verbinden met Spotify is mislukt. Probeer het opnieuw." });
    }
  });

  /** Disconnect the Spotify account. */
  r.post("/media/spotify/disconnect", requireAuth, (_req, res) => {
    spotify.disconnect();
    res.json({ ok: true });
  });

  return r;
}

/* ------------------------------- helpers ----------------------------- */

async function proxySnapshot(
  req: import("express").Request,
  res: import("express").Response,
  kind: "camera" | "intercom",
  mediaBase: string
) {
  const cfg = getConfig();
  const target =
    kind === "camera"
      ? collectCameras(cfg).find((c) => c.id === req.params.id)
      : collectIntercoms(cfg).find((i) => i.id === req.params.id);
  if (!target) return res.status(404).end();

  const cacheKey = `${kind}:${target.id}`;
  const cached = snapshotCache.get(cacheKey);
  const now = Date.now();

  // Stale-while-revalidate: return the last good frame immediately, refresh in background.
  if (serveSnapshotFromCache(res, cacheKey, cached, now)) {
    triggerBackgroundSnapshotRefresh(kind, target, mediaBase, cached, now);
    return;
  }

  const buf = await refreshSnapshotCache(kind, target, mediaBase);
  if (buf) {
    res.setHeader("content-type", "image/jpeg");
    res.setHeader("cache-control", "public, max-age=2");
    return res.end(buf);
  }

  return res.status(502).json({ error: "snapshot unavailable" });
}

async function forwardSignalling(
  req: import("express").Request,
  res: import("express").Response,
  streamPath: string,
  mediaBase: string
) {
  try {
    const url = `${mediaBase}/api/webrtc?src=${encodeURIComponent(streamPath)}`;
    const upstream = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(req.body)
    });
    const text = await upstream.text();
    res
      .status(upstream.status)
      .setHeader(
        "content-type",
        upstream.headers.get("content-type") ?? "application/json"
      )
      .send(text);
  } catch (err) {
    logger.warn({ err }, "webrtc signalling failed");
    res.status(502).json({ error: "signalling failed" });
  }
}

/** Rewrite go2rtc segment URLs so clients only talk to the backend. */
function rewriteHlsPlaylist(
  body: string,
  camId: string,
  clientBase: string,
  mediaBase: string
): string {
  const segBase = `${clientBase.replace(/\/+$/, "")}/api/cameras/${camId}/hls-seg`;
  const mediaOrigin = mediaBase.replace(/\/+$/, "");

  return body
    .split("\n")
    .map((line) => {
      const t = line.trim();
      if (!t || t.startsWith("#")) return line;
      if (t.startsWith("http://") || t.startsWith("https://")) {
        if (t.startsWith(`${mediaOrigin}/api/`)) {
          return `${segBase}${t.slice(mediaOrigin.length + 4)}`;
        }
        return line;
      }
      if (t.startsWith("/api/")) {
        return `${segBase}${t.slice(4)}`;
      }
      return line;
    })
    .join("\n");
}

async function proxyHlsBody(
  res: import("express").Response,
  upstreamUrl: string
) {
  const upstream = await fetch(upstreamUrl, {
    signal: AbortSignal.timeout(15_000)
  });
  if (!upstream.ok) {
    res.status(upstream.status).end();
    return;
  }
  const ct = upstream.headers.get("content-type");
  if (ct) res.setHeader("content-type", ct);
  const cc = upstream.headers.get("cache-control");
  if (cc) res.setHeader("cache-control", cc);
  res.end(Buffer.from(await upstream.arrayBuffer()));
}
