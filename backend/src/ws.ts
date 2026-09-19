import type { Server } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import jwt from "jsonwebtoken";
import { logger } from "./logger";
import type { KnxBus } from "./knxBus";
import type { GAState, MediaState } from "./types";
import { getConfig, getConfigVersion } from "./config";
import { buildDoorbellIndex } from "./intercoms";
import type { TokenPayload } from "./auth";
import { collectIntercoms } from "./cameras";
import type { IntercomDevice } from "./types";
import type { MediaManager } from "./media/manager";
import { hvacSwitchLock, type HvacLockEntry } from "./hvacSwitchLock";
import { fireplaceVirtual, type FireplaceVirtualEntry } from "./fireplaceVirtual";
import { wtwRuntime, type WtwLogicStatus } from "./wtwRuntime";
import { captureOnIntercomRing } from "./intercomCaptures";
import { userIdsInVoipGroup } from "./voip/ringTargets";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";
if (
  SECRET === "dev-secret-change-me" &&
  process.env.NODE_ENV === "production"
) {
  throw new Error(
    "JWT_SECRET env niet gezet — weiger te starten in production."
  );
}

type Outgoing =
  | { type: "snapshot"; payload: GAState[] }
  | { type: "state"; payload: GAState }
  | { type: "media.snapshot"; payload: MediaState[] }
  | { type: "media.state"; payload: MediaState }
  | { type: "hvac.lock.snapshot"; payload: HvacLockEntry[] }
  | { type: "hvac.lock"; payload: HvacLockEntry }
  | { type: "fireplace.virtual.snapshot"; payload: FireplaceVirtualEntry[] }
  | { type: "fireplace.virtual"; payload: FireplaceVirtualEntry }
  | { type: "wtw.logic.snapshot"; payload: WtwLogicStatus[] }
  | {
      type: "intercom.ring";
      payload: { intercomId: string; name: string; ts: number };
    }
  | {
      type: "intercom.cleared";
      payload: { intercomId: string };
    }
  | { type: "config_changed"; payload: { version: number } }
  | {
      type: "scene.heard";
      payload: {
        roomId: string;
        ga: string;
        number: number;
        trusted: boolean;
        timeout?: boolean;
        memberIds?: string[];
        reason?: string;
        existingId?: string;
        existingName?: string;
        members?: unknown[];
        phase?: string;
        src?: string;
        switchName?: string;
        buttonName?: string;
        sceneName?: string;
      };
    };

export interface WsHub {
  broadcastIntercomRing(intercomId: string, groupId?: string): void;
  broadcastIntercomCleared(intercomId: string): void;
  broadcastConfigChanged(version: number): void;
  broadcastSceneHeard(payload: {
    roomId: string;
    ga: string;
    number: number;
    trusted: boolean;
    timeout?: boolean;
    memberIds?: string[];
    reason?: string;
    existingId?: string;
    existingName?: string;
    members?: unknown[];
    phase?: string;
    src?: string;
    switchName?: string;
    buttonName?: string;
    sceneName?: string;
  }): void;
  close(): Promise<void>;
}

export function attachWebSocket(
  server: Server,
  bus: KnxBus,
  media: MediaManager
): WsHub {
  const wss = new WebSocketServer({ server, path: "/ws" });

  const broadcastAll = (msg: Outgoing) => {
    const data = JSON.stringify(msg);
    for (const client of wss.clients) {
      if (client.readyState === client.OPEN) client.send(data);
    }
  };

  const unsubHvac = hvacSwitchLock.onChange((entry) => {
    broadcastAll({ type: "hvac.lock", payload: entry });
  });

  const unsubFireplace = fireplaceVirtual.onChange((entry) => {
    broadcastAll({ type: "fireplace.virtual", payload: entry });
  });

  const unsubWtwLogic = wtwRuntime.onChange((runs) => {
    broadcastAll({ type: "wtw.logic.snapshot", payload: runs });
  });

  const wsUser = new WeakMap<WebSocket, string>();

  wss.on("connection", (ws, req) => {
    const url = new URL(req.url ?? "/ws", "http://localhost");
    const token = url.searchParams.get("token");
    if (!token) {
      ws.close(4401, "missing token");
      return;
    }
    try {
      const decoded = jwt.verify(token, SECRET) as TokenPayload;
      if (decoded.sub) wsUser.set(ws, decoded.sub);
    } catch {
      ws.close(4401, "invalid token");
      return;
    }

    logger.info({ ip: req.socket.remoteAddress }, "WS client connected");
    send(ws, { type: "snapshot", payload: bus.getAll() });
    send(ws, { type: "media.snapshot", payload: media.getAll() });
    send(ws, { type: "hvac.lock.snapshot", payload: hvacSwitchLock.getAll() });
    send(ws, {
      type: "fireplace.virtual.snapshot",
      payload: fireplaceVirtual.getAll()
    });
    send(ws, { type: "wtw.logic.snapshot", payload: wtwRuntime.getAll() });
  });

  let idxVersion = -1;
  let idx: Map<string, IntercomDevice> = new Map();
  const prevValues = new Map<string, GAState["value"]>();

  const onMediaState = (state: MediaState) => {
    broadcastAll({ type: "media.state", payload: state });
  };

  const onBusState = (state: GAState) => {
    broadcastAll({ type: "state", payload: state });

    // Rebuild doorbell index only when config changes.
    if (getConfigVersion() !== idxVersion) {
      idx = buildDoorbellIndex(getConfig());
      idxVersion = getConfigVersion();
    }

    const intercom = idx.get(state.ga);
    if (!intercom) return;

    // Rising edge only – ignore the automatic 0-write that often follows.
    const prev = prevValues.get(state.ga);
    prevValues.set(state.ga, state.value);
    const nowHigh = state.value === true || state.value === 1;
    const wasHigh = prev === true || prev === 1;
    if (nowHigh && !wasHigh) {
      logger.info({ id: intercom.id, ga: state.ga }, "doorbell ring");
      broadcastAll({
        type: "intercom.ring",
        payload: { intercomId: intercom.id, name: intercom.name, ts: Date.now() }
      });
      captureOnIntercomRing(intercom.id);
    }
  };

  media.on("stateChanged", onMediaState);
  bus.on("stateChanged", onBusState);

  return {
    broadcastIntercomRing(intercomId: string, groupId?: string) {
      const cfg = getConfig();
      // Use collectIntercoms (not buildDoorbellIndex) so intercoms without
      // a KNX doorbell.ga (e.g. DoorBird webhook / SIP) are also found.
      const found = collectIntercoms(cfg).find((i) => i.id === intercomId);
      if (!found) return;
      const msg: Outgoing = {
        type: "intercom.ring",
        payload: { intercomId: found.id, name: found.name, ts: Date.now() }
      };
      const gid = groupId?.trim() ?? "";
      if (!gid) {
        broadcastAll(msg);
      } else {
        const allowed = userIdsInVoipGroup(cfg, gid);
        const data = JSON.stringify(msg);
        for (const client of wss.clients) {
          if (client.readyState !== client.OPEN) continue;
          const uid = wsUser.get(client);
          if (uid && allowed.has(uid)) client.send(data);
        }
      }
      captureOnIntercomRing(found.id);
    },
    broadcastIntercomCleared(intercomId: string) {
      broadcastAll({
        type: "intercom.cleared",
        payload: { intercomId }
      });
    },
    broadcastConfigChanged(version: number) {
      broadcastAll({ type: "config_changed", payload: { version } });
      // Devices may have been removed — renew KNX snapshot for open clients.
      broadcastAll({ type: "snapshot", payload: bus.getAll() });
    },
    broadcastSceneHeard(payload) {
      broadcastAll({ type: "scene.heard", payload });
    },
    async close() {
      unsubHvac();
      unsubFireplace();
      unsubWtwLogic();
      media.off("stateChanged", onMediaState);
      bus.off("stateChanged", onBusState);
      for (const client of wss.clients) {
        try {
          client.terminate();
        } catch {
          /* ignore */
        }
      }
      await Promise.race([
        new Promise<void>((resolve) => {
          wss.close(() => resolve());
        }),
        new Promise<void>((resolve) => setTimeout(resolve, 1500))
      ]);
    }
  };
}

function send(ws: WebSocket, msg: Outgoing) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}
