import type { Server } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import jwt from "jsonwebtoken";
import { logger } from "./logger";
import type { KnxBus } from "./knxBus";
import type { GAState, MediaState } from "./types";
import { getConfig, getConfigVersion } from "./config";
import { buildDoorbellIndex } from "./intercoms";
import { collectIntercoms } from "./cameras";
import type { IntercomDevice } from "./types";
import type { MediaManager } from "./media/manager";
import { hvacSwitchLock, type HvacLockEntry } from "./hvacSwitchLock";
import { fireplaceVirtual, type FireplaceVirtualEntry } from "./fireplaceVirtual";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";

type Outgoing =
  | { type: "snapshot"; payload: GAState[] }
  | { type: "state"; payload: GAState }
  | { type: "media.snapshot"; payload: MediaState[] }
  | { type: "media.state"; payload: MediaState }
  | { type: "hvac.lock.snapshot"; payload: HvacLockEntry[] }
  | { type: "hvac.lock"; payload: HvacLockEntry }
  | { type: "fireplace.virtual.snapshot"; payload: FireplaceVirtualEntry[] }
  | { type: "fireplace.virtual"; payload: FireplaceVirtualEntry }
  | {
      type: "intercom.ring";
      payload: { intercomId: string; name: string; ts: number };
    }
  | { type: "config_changed"; payload: { version: number } };

export interface WsHub {
  broadcastIntercomRing(intercomId: string): void;
  broadcastConfigChanged(version: number): void;
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

  wss.on("connection", (ws, req) => {
    const url = new URL(req.url ?? "/ws", "http://localhost");
    const token = url.searchParams.get("token");
    if (!token) {
      ws.close(4401, "missing token");
      return;
    }
    try {
      jwt.verify(token, SECRET);
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
    }
  };

  media.on("stateChanged", onMediaState);
  bus.on("stateChanged", onBusState);

  return {
    broadcastIntercomRing(intercomId: string) {
      const cfg = getConfig();
      // Use collectIntercoms (not buildDoorbellIndex) so intercoms without
      // a KNX doorbell.ga (e.g. DoorBird webhook / SIP) are also found.
      const found = collectIntercoms(cfg).find((i) => i.id === intercomId);
      if (!found) return;
      broadcastAll({
        type: "intercom.ring",
        payload: { intercomId: found.id, name: found.name, ts: Date.now() }
      });
    },
    broadcastConfigChanged(version: number) {
      broadcastAll({ type: "config_changed", payload: { version } });
      // Devices may have been removed — renew KNX snapshot for open clients.
      broadcastAll({ type: "snapshot", payload: bus.getAll() });
    },
    async close() {
      unsubHvac();
      unsubFireplace();
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
