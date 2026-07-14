// Server-side time-series storage for KNX group-address values.
//
// Samples are written on *change* (the sampler dedupes consecutive equal
// values) into a small SQLite database under backend/data/logs.db. History
// queries return downsampled series so zooming out stays fast, and old
// samples are pruned by the sampler (default 90 days).

import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { logger } from "./logger";

export interface LogSample {
  ts: number;
  value: number;
}

function dbPath(): string {
  const fromEnv = process.env.LOG_STORE_PATH?.trim();
  if (fromEnv) return path.resolve(fromEnv);
  return path.join(process.cwd(), "data", "logs.db");
}

export class LogStore {
  private readonly db: Database.Database;
  private readonly insertStmt: Database.Statement;
  private readonly inRangeStmt: Database.Statement;
  private readonly anchorStmt: Database.Statement;
  /** Latest numeric value per GA — used to dedupe unchanged telegrams. */
  private readonly lastValue = new Map<string, number>();

  constructor() {
    const file = dbPath();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    this.db = new Database(file);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("synchronous = NORMAL");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS samples (
        ga TEXT NOT NULL,
        ts INTEGER NOT NULL,
        value REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_samples_ga_ts ON samples(ga, ts);
    `);
    this.insertStmt = this.db.prepare(
      "INSERT INTO samples (ga, ts, value) VALUES (?, ?, ?)"
    );
    this.inRangeStmt = this.db.prepare(
      "SELECT ts, value FROM samples WHERE ga = ? AND ts >= ? AND ts <= ? ORDER BY ts ASC"
    );
    this.anchorStmt = this.db.prepare(
      "SELECT ts, value FROM samples WHERE ga = ? AND ts < ? ORDER BY ts DESC LIMIT 1"
    );

    // Seed the dedupe cache with the most recent value per GA.
    try {
      const rows = this.db
        .prepare(
          `SELECT ga, value FROM samples s
           WHERE ts = (SELECT MAX(ts) FROM samples WHERE ga = s.ga)`
        )
        .all() as { ga: string; value: number }[];
      for (const row of rows) this.lastValue.set(row.ga, row.value);
    } catch (err) {
      logger.warn({ err }, "logStore: kon laatste waarden niet laden");
    }
  }

  /** Record a numeric sample. Non-numeric and unchanged values are ignored. */
  record(ga: string, value: unknown, ts: number = Date.now()): void {
    const num = toNumeric(value);
    if (num === null) return;
    if (this.lastValue.get(ga) === num) return;
    try {
      this.insertStmt.run(ga, ts, num);
      this.lastValue.set(ga, num);
    } catch (err) {
      logger.warn({ err, ga }, "logStore: sample opslaan mislukt");
    }
  }

  /**
   * Return downsampled history for each GA within [from, to]. A synthetic
   * anchor point at `from` carries the last value before the window so the
   * line starts at the left edge instead of mid-chart.
   */
  query(
    gas: string[],
    from: number,
    to: number,
    maxPoints = 500
  ): Record<string, LogSample[]> {
    const out: Record<string, LogSample[]> = {};
    for (const ga of gas) {
      const rows = this.inRangeStmt.all(ga, from, to) as LogSample[];
      const points: LogSample[] = [];
      const anchor = this.anchorStmt.get(ga, from) as LogSample | undefined;
      if (anchor) points.push({ ts: from, value: anchor.value });
      points.push(...rows);
      out[ga] = downsample(points, maxPoints);
    }
    return out;
  }

  /** Delete samples older than `maxAgeMs`. Returns the number removed. */
  prune(maxAgeMs: number): number {
    const cutoff = Date.now() - maxAgeMs;
    try {
      const info = this.db.prepare("DELETE FROM samples WHERE ts < ?").run(cutoff);
      return info.changes;
    } catch (err) {
      logger.warn({ err }, "logStore: opschonen mislukt");
      return 0;
    }
  }

  close(): void {
    try {
      this.db.close();
    } catch {
      /* ignore */
    }
  }
}

function toNumeric(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "boolean") return value ? 1 : 0;
  return null;
}

/** Bucket-average downsampling to at most `maxPoints` points. */
function downsample(points: LogSample[], maxPoints: number): LogSample[] {
  if (points.length <= maxPoints) return points;
  const from = points[0].ts;
  const to = points[points.length - 1].ts;
  const span = to - from || 1;

  interface Bucket {
    tsSum: number;
    valSum: number;
    n: number;
  }
  const buckets: (Bucket | undefined)[] = new Array(maxPoints);
  for (const p of points) {
    let idx = Math.floor(((p.ts - from) / span) * maxPoints);
    if (idx < 0) idx = 0;
    if (idx >= maxPoints) idx = maxPoints - 1;
    const b = buckets[idx] ?? { tsSum: 0, valSum: 0, n: 0 };
    b.tsSum += p.ts;
    b.valSum += p.value;
    b.n += 1;
    buckets[idx] = b;
  }

  const out: LogSample[] = [];
  for (const b of buckets) {
    if (!b) continue;
    out.push({ ts: Math.round(b.tsSum / b.n), value: b.valSum / b.n });
  }
  return out;
}
