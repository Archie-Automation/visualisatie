import { getConfig, walkDevices } from "./config";
import { logger } from "./logger";
import type { KnxBus } from "./knxBus";
import type { MediaManager } from "./media/manager";
import type { LutronIntegrationManager } from "./lutron/manager";

/** JSON-safe view for logs and GET /api/health (no secrets). */
export type ConnectivitySnapshot = {
  knx: {
    connected: boolean;
    simulate: boolean;
    disabled: boolean;
    host: string;
    port: number;
  };
  media: { id: string; name: string; brand: string; online: boolean }[];
  lutron: {
    deviceId: string;
    name: string;
    host: string;
    port: number;
    connected: boolean;
    loggedIn: boolean;
  }[];
};

function mediaDisplayNames(): Map<string, string> {
  const m = new Map<string, string>();
  walkDevices(getConfig(), (d) => {
    if (d.type === "media_sonos" || d.type === "media_bluesound") {
      m.set(d.id, d.name);
    }
  });
  return m;
}

export function getConnectivitySnapshot(
  bus: KnxBus,
  media: MediaManager,
  lutron: LutronIntegrationManager
): ConnectivitySnapshot {
  const knx = bus.getStatus();
  const names = mediaDisplayNames();
  const mediaRows = media.getAll().map((s) => ({
    id: s.deviceId,
    name: names.get(s.deviceId) ?? s.deviceId,
    brand: s.brand,
    online: s.online
  }));
  const lutronRows = lutron.getStatus().map((s) => ({
    deviceId: s.deviceId,
    name: s.name,
    host: s.host,
    port: s.port,
    connected: s.connected,
    loggedIn: s.loggedIn
  }));
  return { knx: { ...knx }, media: mediaRows, lutron: lutronRows };
}

/** One consolidated line after external services had time to connect. */
export function logStartupConnectivityReport(snap: ConnectivitySnapshot): void {
  const issuesNl: string[] = [];
  const { knx, media } = snap;

  if (!knx.disabled && !knx.simulate && !knx.connected) {
    issuesNl.push(
      `KNX-bus: geen verbinding met gateway ${knx.host}:${knx.port} (controleer netwerk / IP / poort 3671).`
    );
  }

  for (const row of media) {
    if (!row.online) {
      issuesNl.push(
        `Media (${row.brand}) “${row.name}” (${row.id}): nog offline of niet bereikbaar.`
      );
    }
  }

  for (const row of snap.lutron) {
    if (!row.connected) {
      issuesNl.push(
        `Lutron Homeworks “${row.name}” (${row.deviceId}): telnet niet verbonden met ${row.host}:${row.port}.`
      );
    }
  }

  if (issuesNl.length === 0) {
    logger.info(
      {
        knx: knx.disabled ? "disabled" : knx.simulate ? "simulate" : "connected",
        mediaOnline: media.filter((x) => x.online).length,
        mediaTotal: media.length,
        lutronConnected: snap.lutron.filter((x) => x.connected).length,
        lutronTotal: snap.lutron.length
      },
      knx.simulate
        ? "Externe verbindingen: KNX-simulatie actief; media/Lutron zoals geconfigureerd."
        : "Externe verbindingen: alles OK (KNX + media + Lutron zoals geconfigureerd)."
    );
    return;
  }

  logger.warn(
    {
      issues: issuesNl,
      connectivity: snap
    },
    "Externe verbindingen: niet alles OK; de API blijft wel draaien (details in issues[])."
  );
}
