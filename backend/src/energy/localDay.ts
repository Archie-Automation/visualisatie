/**
 * Local-day boundaries via Intl. Same approach as the scheduler, kept here
 * so energy math does not pull in SunCalc.
 */

export function startOfLocalDay(base: Date, tz: string): Date {
  const parts = localParts(base, tz);
  return fromLocal(parts.year, parts.month, parts.day, 0, 0, tz);
}

/** The next local midnight strictly after `startOfLocalDay(now)`. */
export function nextLocalMidnight(now: Date, tz: string): Date {
  const start = startOfLocalDay(now, tz);
  for (let hours = 20; hours <= 30; hours++) {
    const probe = new Date(start.getTime() + hours * 3_600_000);
    const next = startOfLocalDay(probe, tz);
    if (next.getTime() > start.getTime()) return next;
  }
  return new Date(start.getTime() + 24 * 3_600_000);
}

export function addLocalDays(now: Date, days: number, tz: string): Date {
  let cursor = startOfLocalDay(now, tz);
  for (let i = 0; i < days; i++) cursor = nextLocalMidnight(cursor, tz);
  return cursor;
}

function localParts(d: Date, tz: string): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
} {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
  const parts = f.formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")) % 24,
    minute: Number(get("minute"))
  };
}

function fromLocal(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  tz: string
): Date {
  const guess = new Date(Date.UTC(year, month - 1, day, hour, minute));
  const observed = localParts(guess, tz);
  const desiredMin =
    (year * 12 * 31 + month * 31 + day) * 24 * 60 + hour * 60 + minute;
  const observedMin =
    (observed.year * 12 * 31 + observed.month * 31 + observed.day) * 24 * 60 +
    observed.hour * 60 +
    observed.minute;
  return new Date(guess.getTime() + (desiredMin - observedMin) * 60_000);
}
