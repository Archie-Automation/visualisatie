// Records logged group-address values as they change and prunes old data.
//
// Subscribes to the KNX bus `stateChanged` event and forwards values for the
// tracked GAs (climate temps + custom logs) into the LogStore. The tracked
// set is recomputed from the config on start and after every installer save.

import { getConfig } from "./config";
import { computeTrackedGas } from "./logDefs";
import { logger } from "./logger";
import type { KnxBus } from "./knxBus";
import type { LogStore } from "./logStore";
import type { GA, GAState } from "./types";

export interface LogSamplerHandle {
  /** Recompute the tracked GA set from the current config. Call after saves. */
  refresh(): void;
  stop(): void;
}

const DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_MS =
  Math.max(1, Number(process.env.LOG_RETENTION_DAYS ?? 90)) * DAY_MS;

export function startLogSampler(bus: KnxBus, store: LogStore): LogSamplerHandle {
  let tracked = new Set<GA>();

  const onState = (s: GAState) => {
    if (!tracked.has(s.ga)) return;
    store.record(s.ga, s.value, s.ts);
  };
  bus.on("stateChanged", onState);

  /**
   * Write a baseline sample for every tracked GA from the current bus cache.
   * This gives graphs (and the heat/cool band) a starting value to hold, so a
   * line/band doesn't begin only at the first change after logging started.
   */
  function seed() {
    for (const ga of tracked) {
      const st = bus.getState(ga);
      if (st) store.record(ga, st.value, st.ts);
    }
  }

  // Re-seed once the bus (re)connects and values are populated.
  const onConnected = () => seed();
  bus.on("connected", onConnected);

  function refresh() {
    tracked = computeTrackedGas(getConfig());
    seed();
    logger.info(
      { count: tracked.size },
      "logSampler: gevolgde groepsadressen bijgewerkt"
    );
  }
  refresh();

  const pruneNow = () => {
    const removed = store.prune(RETENTION_MS);
    if (removed > 0) {
      logger.info({ removed }, "logSampler: oude samples opgeruimd");
    }
  };
  pruneNow();
  const pruneTimer = setInterval(pruneNow, DAY_MS);
  pruneTimer.unref?.();

  return {
    refresh,
    stop() {
      bus.off("stateChanged", onState);
      bus.off("connected", onConnected);
      clearInterval(pruneTimer);
    }
  };
}
