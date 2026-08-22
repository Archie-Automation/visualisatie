// Time + astro scheduler. Computes the next trigger for every enabled
// schedule and fires its action. Uses `suncalc` for sunrise/sunset. All
// clock math is done in the project's configured IANA time zone so DST
// transitions don't accidentally fire scenes twice.
//
// We don't try to be a cron replacement — schedules here fire at most
// once per day per entry. That matches the user-facing mental model
// ("every weekday at sunset") and keeps the engine tiny.

import * as SunCalc from "suncalc";
import { logger } from "./logger";
import { findScene, getConfig, updateConfig } from "./config";
import { runScene } from "./scenes";
import type { KnxBus } from "./knxBus";
import type { MediaManager } from "./media/manager";
import type {
  Schedule,
  ScheduleAction,
  ScheduleGuard,
  ScheduleTrigger,
  SceneAction,
  HouseConfig
} from "./types";

export interface SchedulerHandle {
  /** Rebuild the timer table from the current config. Call after writes. */
  reschedule(): void;
  /** Run a single schedule right now, ignoring its trigger. */
  runNow(id: string): Promise<void>;
  stop(): void;
}

export function startScheduler(bus: KnxBus, media: MediaManager): SchedulerHandle {
  /** Map from schedule id → its outstanding timeout handle. */
  const timers = new Map<string, NodeJS.Timeout>();
  let stopped = false;

  function clearTimers() {
    for (const t of timers.values()) clearTimeout(t);
    timers.clear();
  }

  function scheduleOne(s: Schedule) {
    if (!s.enabled) return;
    const cfg = getConfig();
    const next = nextFireTime(s.trigger, cfg, new Date());
    if (!next) {
      logger.debug({ id: s.id }, "schedule: no next fire time");
      return;
    }
    const delayMs = next.getTime() - Date.now();
    if (delayMs <= 0) return;
    // `setTimeout` is capped at ~24.8 days on Node, so we're safe here.
    const handle = setTimeout(async () => {
      timers.delete(s.id);
      try {
        await fire(s, bus, media);
        markRan(s.id);
      } catch (err) {
        logger.warn({ err, id: s.id }, "schedule fire failed");
      }
      // Reschedule the *same* entry for its next occurrence (tomorrow, usually).
      if (!stopped) scheduleOne(getScheduleById(s.id) ?? s);
    }, delayMs);
    timers.set(s.id, handle);
    logger.info(
      { id: s.id, name: s.name, next: next.toISOString() },
      "schedule armed"
    );
  }

  function rescheduleAll() {
    clearTimers();
    const cfg = getConfig();
    for (const s of cfg.schedules ?? []) scheduleOne(s);
  }

  rescheduleAll();

  return {
    reschedule: rescheduleAll,
    async runNow(id) {
      const s = getScheduleById(id);
      if (!s) throw new Error("unknown schedule");
      await fire(s, bus, media);
      markRan(id);
    },
    stop() {
      stopped = true;
      clearTimers();
    }
  };
}

/* ---------------------------- fire helpers ---------------------------- */

async function fire(s: Schedule, bus: KnxBus, media: MediaManager) {
  logger.info({ id: s.id, name: s.name, trigger: s.trigger.kind }, "schedule fire");
  await executeAction(s.action, bus, media);
}

async function executeAction(
  action: ScheduleAction,
  bus: KnxBus,
  media: MediaManager
) {
  if (action.kind === "scene") {
    const cfg = getConfig();
    const steps =
      action.steps && action.steps.length > 0
        ? action.steps
        : [{ sceneId: action.sceneId }];
    for (const step of steps) {
      if (step.delayMs && step.delayMs > 0) {
        await new Promise<void>((r) => setTimeout(r, step.delayMs));
      }
      const hit = findScene(cfg, step.sceneId);
      if (!hit) {
        logger.warn(
          { sceneId: step.sceneId },
          "schedule: scene no longer exists"
        );
        continue;
      }
      await runScene(hit.scene, bus, cfg, media);
    }
    return;
  }
  await runActionList(action.actions, bus, media);
}

async function runActionList(
  actions: SceneAction[],
  bus: KnxBus,
  media: MediaManager
) {
  const synth = { id: "__schedule_adhoc__", name: "schedule", actions };
  await runScene(synth, bus, getConfig(), media);
}

function getScheduleById(id: string): Schedule | undefined {
  return (getConfig().schedules ?? []).find((x) => x.id === id);
}

function markRan(id: string) {
  try {
    updateConfig((draft) => {
      const s = (draft.schedules ?? []).find((x) => x.id === id);
      if (s) s.lastRun = new Date().toISOString();
    });
  } catch (err) {
    logger.warn({ err, id }, "could not persist lastRun");
  }
}

/* ------------------------------ math ---------------------------------- */

/**
 * Compute the next fire time for a trigger, starting from `from`.
 * Walks forward up to 14 days before giving up – handles "only Sunday
 * sunset" cases and gracefully skips days that fall outside the
 * notBefore/notAfter guards.
 */
export function nextFireTime(
  trigger: ScheduleTrigger,
  cfg: HouseConfig,
  from: Date
): Date | null {
  const tz = cfg.project.timezone ?? "Europe/Amsterdam";
  const loc = cfg.project.location;

  for (let dayShift = 0; dayShift < 14; dayShift++) {
    const candidateDay = addDays(startOfLocalDay(from, tz), dayShift);

    if (!allowedOnWeekday(trigger.days, candidateDay, tz)) continue;

    let t: Date | null;
    if (trigger.kind === "time") {
      t = atLocalTime(candidateDay, trigger.time, tz);
    } else {
      if (!loc) {
        logger.warn("schedule: astro trigger requires project.location");
        return null;
      }
      const base = sunEvent(candidateDay, trigger.event, loc);
      if (!base) continue;
      t = new Date(base.getTime() + (trigger.offsetMin ?? 0) * 60_000);

      // Apply guards.
      const lower = trigger.notBefore
        ? resolveGuard(trigger.notBefore, candidateDay, cfg)
        : null;
      const upper = trigger.notAfter
        ? resolveGuard(trigger.notAfter, candidateDay, cfg)
        : null;
      if (lower && t < lower) t = lower;
      if (upper && t > upper) continue; // can't fire today at all
    }

    if (t && t > from) return t;
  }
  return null;
}

function resolveGuard(
  g: ScheduleGuard,
  day: Date,
  cfg: HouseConfig
): Date | null {
  const tz = cfg.project.timezone ?? "Europe/Amsterdam";
  if (g.kind === "time") return atLocalTime(day, g.time, tz);
  if (!cfg.project.location) return null;
  const ev = sunEvent(day, g.event, cfg.project.location);
  if (!ev) return null;
  return new Date(ev.getTime() + (g.offsetMin ?? 0) * 60_000);
}

function sunEvent(
  day: Date,
  event: "sunrise" | "sunset",
  loc: { lat: number; lon: number }
): Date | null {
  // `day` is local midnight and may still be the previous UTC date.
  // SunCalc v2 uses the UTC solar day of the input, so probe at local noon.
  const probe = new Date(day.getTime() + 12 * 60 * 60 * 1000);
  const times = SunCalc.getTimes(probe, loc.lat, loc.lon);
  const out = event === "sunrise" ? times.sunrise : times.sunset;
  if (!out) return null;
  if (out instanceof Date && Number.isNaN(out.getTime())) return null;
  return out;
}

/* ------------------------- time zone plumbing ------------------------- */
// We deliberately avoid adding Luxon/date-fns-tz — for the couple of
// operations we need, `Intl.DateTimeFormat` is precise enough and keeps
// the dependency surface small.

function allowedOnWeekday(
  mask: import("./types").WeekdayMask,
  day: Date,
  tz: string
): boolean {
  const parts = localParts(day, tz);
  // parts.weekday is 0=Sun..6=Sat in Intl output — normalize to Mon=0..Sun=6.
  const isoIdx = (parts.weekday + 6) % 7;
  return !!mask[isoIdx];
}

/** Return the UTC Date corresponding to local midnight on the given day. */
function startOfLocalDay(base: Date, tz: string): Date {
  const { year, month, day } = localParts(base, tz);
  // Find a UTC offset such that formatting(`y-m-d 00:00`) in `tz` lines up.
  // Binary search is overkill — one Intl round-trip is enough because tz
  // offsets are always in whole minutes and we only care about "same day".
  return fromLocal(year, month, day, 0, 0, tz);
}

function atLocalTime(day: Date, hhmm: string, tz: string): Date {
  const [h, m] = hhmm.split(":").map((x) => Number(x));
  if (!Number.isFinite(h) || !Number.isFinite(m)) return day;
  const parts = localParts(day, tz);
  return fromLocal(parts.year, parts.month, parts.day, h, m, tz);
}

function addDays(d: Date, n: number): Date {
  const out = new Date(d);
  out.setUTCDate(out.getUTCDate() + n);
  return out;
}

/** Break a Date into local components in the given IANA time zone. */
function localParts(d: Date, tz: string): {
  year: number;
  month: number; // 1..12
  day: number;   // 1..31
  hour: number;
  minute: number;
  weekday: number; // 0 = Sun..6 = Sat
} {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
  const parts = f.formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  const weekdayMap: Record<string, number> = {
    Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6
  };
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24, // Intl returns "24" at midnight on some locales
    minute: Number(get("minute")),
    weekday: weekdayMap[get("weekday")] ?? 0
  };
}

/** Find the UTC instant whose local time in `tz` is the given y/m/d h:m.
 *  We iterate once: compute the UTC candidate assuming UTC, measure the
 *  offset in tz, then correct. Good enough for non-ambiguous wall times
 *  (ambiguity around DST "fall back" resolves to the earlier instant). */
function fromLocal(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  tz: string
): Date {
  // First guess: treat the given numbers as UTC.
  const guess = new Date(Date.UTC(year, month - 1, day, hour, minute));
  // Measure the offset we actually got after rendering in tz.
  const lp = localParts(guess, tz);
  // Difference between desired local and observed local, in minutes.
  const desiredMin =
    (year * 12 * 31 + month * 31 + day) * 24 * 60 + hour * 60 + minute;
  const observedMin =
    (lp.year * 12 * 31 + lp.month * 31 + lp.day) * 24 * 60 +
    lp.hour * 60 +
    lp.minute;
  const diffMin = desiredMin - observedMin;
  return new Date(guess.getTime() + diffMin * 60_000);
}
