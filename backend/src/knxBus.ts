import { EventEmitter } from "node:events";
import { buildGAIndex, collectAllGAs, getConfig } from "./config";
import type { GARole } from "./config";
import { logger } from "./logger";
import type { GA, GAState, HouseConfig, Rgb232Triplet } from "./types";

/**
 * Datapoint types we use per role. The keys match the roles in house.json.
 * See KNX DPT: 1.001 = boolean, 5.001 = percent (0-100), 9.001 = temperature
 * (2-byte float, °C), 20.102 = HVAC mode, 8.001 = 2-byte signed.
 */
export const ROLE_DPT: Record<string, string> = {
  switch: "DPT1.001",
  switch_status: "DPT1.001",
  dim_value: "DPT5.001",
  dim_status: "DPT5.001",
  /** 4-bit dimming control (start up/down + stop). Media volume rocker. */
  dim_control: "DPT3.007",

  up_down: "DPT1.008",
  stop_step: "DPT1.007",
  position: "DPT5.001",
  position_status: "DPT5.001",
  slat: "DPT5.001",
  slat_status: "DPT5.001",
  /** Shading movement feedback (bit). */
  moving: "DPT1.001",

  actual_temp: "DPT9.001",
  setpoint: "DPT9.001",
  setpoint_status: "DPT9.001",
  mode: "DPT20.102",
  mode_status: "DPT20.102",

  // Raw / universal roles – used by scenes and the universal device type.
  bit: "DPT1.001",
  byte: "DPT5.010", // 0..255 unsigned int
  percent: "DPT5.001", // 0..100
  temperature: "DPT9.001", // 2-byte float – also used for all DPT9.x
  raw_int: "DPT5.010",
  /** DPT 18.001 scene control as 1 byte (bit7=store, bits0–5=scene−1). knx.js has no DPT18. */
  scene: "DPT5.010",
  uint16: "DPT7.001",   // 0..65535 unsigned int (e.g. day counter)
  signed_byte: "DPT6.001",   // −128..127 signed byte
  signed_2byte: "DPT8.001",  // 2-byte signed int
  uint32: "DPT12.001",       // 0..4 294 967 295
  int32: "DPT13.001",        // signed 32-bit int
  float4byte: "DPT14.019",   // 4-byte IEEE-754 float (DPT14.x)
  scene_number: "DPT17.001", // 0..63 scene number
  flame: "DPT5.010",
  flame_status: "DPT5.010",
  // Airco (type "ac") only. mode = 1-byte HVAC control-mode enum (DPT 20.105),
  // fanSpeed = percentage (DPT 5.001, raw 0..255 <-> 0..100 %). These roles are
  // NOT shared with `climate` (which keeps mode = DPT 20.102) or other devices.
  ac_mode: "DPT20.105",
  ac_mode_status: "DPT20.105",
  fan_speed: "DPT5.001",

  // RGBW/WW per-kanaal (zelfde DPT als universeel byte).
  r: "DPT5.010",
  g: "DPT5.010",
  b: "DPT5.010",
  w: "DPT5.010",
  ww: "DPT5.010",
  cw: "DPT5.010",
  /** Status/decode: 14-byte string DPT — schrijven gaat via writeRaw. */
  composite: "DPT16.000",
  rgb232: "DPT232.600",
  raw_bytes: "DPT16.000"
};

export interface KnxEvents {
  stateChanged: (state: GAState) => void;
  connected: () => void;
  disconnected: () => void;
  telegram: (info: KnxTelegram) => void;
}

export interface KnxTelegram {
  ga: GA;
  src?: string;
  value: unknown;
  self: boolean;
  ts: number;
  evt: string;
}

export declare interface KnxBus {
  on<E extends keyof KnxEvents>(event: E, listener: KnxEvents[E]): this;
  emit<E extends keyof KnxEvents>(event: E, ...args: Parameters<KnxEvents[E]>): boolean;
}

/**
 * Thin abstraction on top of `knx.js`. When KNX_SIMULATE=1 we keep the
 * exact same interface but never touch the network – round-trips become
 * immediate echoes, so the UI is fully testable on a laptop.
 */
/** Status GAs we read first after connect so the UI is populated quickly. */
const READ_PRIORITY_ROLES = new Set([
  "actual_temp",
  "setpoint_status",
  "setpoint",
  "switch_status",
  "dim_status",
  "position_status",
  "slat_status",
  "mode_status",
  "ac_mode_status",
  "fan_speed",
  "hvac_mode_status",
  "heat_demand",
  "cool_demand",
  "flame_status",
  "temperature"
]);

export class KnxBus extends EventEmitter {
  private readonly cache = new Map<GA, GAState>();
  private readonly gaToDpt = new Map<GA, string>();
  private gaRoles = new Map<GA, GARole[]>();
  private connection: unknown;
  private readonly simulate: boolean;
  /** When true the bus is administratively disabled; connect() is a no-op. */
  private disabled: boolean;
  private readonly datapoints = new Map<GA, unknown>();
  private busConnected = false;
  private readonly selfWrites: Array<{ ga: GA; byte?: number; ts: number }> = [];

  private host: string;
  private port: number;
  private physicalAddress?: string;

  constructor(host: string, port: number = 3671, physicalAddress?: string, disabled = false) {
    super();
    this.host = host;
    this.port = port;
    this.physicalAddress = physicalAddress;
    this.simulate = process.env.KNX_SIMULATE === "1";
    this.disabled = disabled;
  }

  /** Live view of gateway target + socket state (for installer UI). */
  getStatus(): {
    connected: boolean;
    simulate: boolean;
    disabled: boolean;
    host: string;
    port: number;
  } {
    return {
      connected: this.busConnected,
      simulate: this.simulate,
      disabled: this.disabled,
      host: this.host,
      port: this.port
    };
  }

  private applyGateway(cfg: HouseConfig) {
    this.host = process.env.KNX_GATEWAY_HOST ?? cfg.knx?.gateway?.host ?? this.host;
    this.port = Number(process.env.KNX_GATEWAY_PORT ?? cfg.knx?.gateway?.port ?? 3671);
    this.physicalAddress = cfg.knx?.physicalAddress;
    this.disabled = cfg.knx?.enabled === false || !cfg.knx;
  }

  /**
   * Drop the tunnel and open a new one using the current house.json
   * (respects KNX_GATEWAY_HOST / KNX_GATEWAY_PORT overrides).
   */
  async reconnect(): Promise<void> {
    const cfg = getConfig();
    this.applyGateway(cfg);
    await this.disconnect();
    await this.connect(collectAllGAs(cfg));
  }

  async disconnect(): Promise<void> {
    if (this.disabled) return;
    if (this.simulate) {
      this.busConnected = false;
      this.datapoints.clear();
      this.emit("disconnected");
      return;
    }

    const conn = this.connection as
      | { Disconnect?: (cb: () => void) => void }
      | undefined;
    this.connection = undefined;
    this.datapoints.clear();
    this.busConnected = false;

    if (!conn?.Disconnect) return;

    try {
      await new Promise<void>((resolve) => {
        try {
          conn.Disconnect!(() => resolve());
        } catch (err) {
          logger.warn({ err }, "KNX Disconnect() mislukt — verbinding lokaal gewist");
          resolve();
        }
      });
    } catch (err) {
      logger.warn({ err }, "KNX disconnect mislukt — verbinding lokaal gewist");
    }
  }

  async connect(groupAddresses: Iterable<GA>): Promise<void> {
    this.rebuildGaDptMap();
    if (this.disabled) {
      logger.info("KNX uitgeschakeld in configuratie — geen verbindingspoging.");
      return;
    }
    if (this.simulate) {
      logger.warn("KNX simulate mode – no physical bus connection");
      for (const ga of groupAddresses) {
        this.cache.set(ga, { ga, value: 0, ts: Date.now() });
      }
      this.busConnected = true;
      setTimeout(() => this.emit("connected"), 50);
      return;
    }

    const knx = await loadKnxModule();
    return new Promise((resolve, reject) => {
      const conn = knx.Connection({
        ipAddr: this.host,
        ipPort: this.port,
        physAddr: this.physicalAddress,
        handlers: {
          connected: () => {
            logger.info({ host: this.host, port: this.port }, "KNX gateway connected");
            this.bindDatapoints(knx, conn, groupAddresses);
            this.scheduleGroupReads(groupAddresses);
            this.busConnected = true;
            const emitter = conn as { on?: (e: string, fn: () => void) => void };
            emitter.on?.("disconnected", () => {
              this.busConnected = false;
              this.connection = undefined;
              this.datapoints.clear();
              this.emit("disconnected");
            });
            this.emit("connected");
            resolve();
          },
          error: (err: Error) => {
            logger.error({ err }, "KNX connection error");
            this.busConnected = false;
            this.connection = undefined;
            this.datapoints.clear();
            this.emit("disconnected");
            reject(err);
          },
          event: (evt: string, src: string, dest: GA, value: unknown) => {
            if (evt !== "GroupValue_Write" && evt !== "GroupValue_Response") return;
            const byte = extractByte(value);
            const self = this.isSelfWrite(dest, byte);
            this.emit("telegram", { ga: dest, src, value, self, ts: Date.now(), evt });
            if (evt === "GroupValue_Write" && self) return;
            this.onBusTelegram(dest, value);
          }
        }
      });
      this.connection = conn;
    });
  }

  /**
   * Re-subscribe group addresses after house.json changes (installer save
   * or reload) without restarting the process.
   */
  async refreshGroupAddresses(groupAddresses: Iterable<GA>): Promise<void> {
    this.rebuildGaDptMap();
    const wanted = new Set(groupAddresses);

    if (this.simulate) {
      for (const ga of [...this.cache.keys()]) {
        if (!wanted.has(ga)) this.cache.delete(ga);
      }
      for (const ga of wanted) {
        if (!this.cache.has(ga))
          this.cache.set(ga, { ga, value: 0, ts: Date.now() });
      }
      return;
    }

    if (!this.connection) {
      logger.warn("KNX not connected – skipping GA refresh (use reconnect in installer)");
      return;
    }

    const knx = await loadKnxModule();
    for (const ga of [...this.datapoints.keys()]) {
      if (!wanted.has(ga)) {
        this.datapoints.delete(ga);
        this.cache.delete(ga);
      }
    }

    const added: GA[] = [];
    for (const ga of wanted) {
      if (this.datapoints.has(ga)) continue;
      const dpt = this.gaToDpt.get(ga) ?? "DPT1.001";
      try {
        const dp = new knx.Datapoint({ ga, dpt }, this.connection as never);
        this.datapoints.set(ga, dp);
        added.push(ga);
      } catch (err) {
        logger.warn({ err, ga }, "Failed to bind datapoint on refresh");
      }
    }

    if (added.length > 0) this.scheduleGroupReads(added);
    logger.info({ count: this.datapoints.size }, "KNX group addresses refreshed");
  }

  private rebuildGaDptMap(): void {
    this.gaToDpt.clear();
    this.gaRoles = buildGAIndex(getConfig());
    for (const [ga, roles] of this.gaRoles) {
      this.gaToDpt.set(ga, this.pickDptForGa(roles));
    }
  }

  private pickDptForGa(roles: GARole[]): string {
    if (roles.some((r) => r.role === "dim_control")) return "DPT3.007";
    const dpts = [
      ...new Set(roles.map((r) => ROLE_DPT[r.role]).filter(Boolean))
    ] as string[];
    if (dpts.length === 0) return "DPT1.001";
    if (dpts.length === 1) return dpts[0];
    logger.warn(
      { roles: roles.map((r) => r.role) },
      "Conflicting DPT roles for GA - using first match"
    );
    return dpts[0];
  }

  private normalizeDecoded(raw: unknown): number | boolean | string | Rgb232Triplet {
    if (typeof raw === "number" || typeof raw === "boolean" || typeof raw === "string") {
      return raw;
    }
    const nibble = dimObjectToNibble(raw);
    if (nibble != null) return nibble;
    if (raw != null && typeof raw === "object" && "red" in raw && "green" in raw && "blue" in raw) {
      const o = raw as Record<string, unknown>;
      return {
        red: Number(o.red),
        green: Number(o.green),
        blue: Number(o.blue)
      };
    }
    if (raw == null) return false;
    logger.warn({ raw }, "KNX decoded value has unexpected type");
    return String(raw);
  }

  /**
   * When one GA serves multiple roles (e.g. switch + actual_temp), pick the
   * DPT that matches the telegram payload size instead of always using the
   * first role from config.
   */
  private resolveDptForTelegram(ga: GA, buf: Buffer): string {
    const roles = this.gaRoles.get(ga) ?? [];
    const dpts = [
      ...new Set(roles.map((r) => ROLE_DPT[r.role]).filter(Boolean))
    ] as string[];
    if (dpts.length <= 1) return dpts[0] ?? this.gaToDpt.get(ga) ?? "DPT1.001";

    if (buf.length >= 2) {
      const temp = dpts.find((d) => d.startsWith("DPT9") || d === "DPT14.019");
      if (temp) return temp;
      const numeric = dpts.find((d) =>
        ["DPT5.001", "DPT5.010", "DPT7.001", "DPT8.001", "DPT20.102"].includes(d)
      );
      if (numeric) return numeric;
    }
    if (buf.length <= 1) {
      const dim = dpts.find((d) => d === "DPT3.007" || d.startsWith("DPT3"));
      if (dim) return dim;
      const bit = dpts.find((d) => d.startsWith("DPT1"));
      if (bit) return bit;
    }
    return dpts[0];
  }

  private decodeBuffer(
    dest: GA,
    buf: Buffer
  ): { decoded: number | boolean | string | Rgb232Triplet; dptId: string; ignore?: boolean } {
    const primary = this.resolveDptForTelegram(dest, buf);
    if (primary.startsWith("DPT3") && buf.length === 0) {
      return { decoded: 0, dptId: primary, ignore: true };
    }
    const fallback = this.gaToDpt.get(dest);
    const candidates = [
      primary,
      ...(fallback && fallback !== primary ? [fallback] : [])
    ];
    const DPTLib = loadDptLib();
    for (const dptId of candidates) {
      try {
        const raw = DPTLib.fromBuffer(buf, DPTLib.resolve(dptId));
        return { decoded: this.normalizeDecoded(raw), dptId };
      } catch {
        /* try next candidate */
      }
    }
    logger.warn(
      { dest, bufLen: buf.length, candidates },
      "KNX telegram decode failed for all DPT candidates"
    );
    if (primary.startsWith("DPT3")) {
      return {
        decoded: buf.length > 0 ? buf[0] & 0x0f : 0,
        dptId: primary,
        ignore: buf.length === 0
      };
    }
    return {
      decoded: buf.length > 0 ? Boolean(buf[0] & 0x01) : false,
      dptId: primary
    };
  }

  private onBusTelegram(dest: GA, value: unknown): void {
    let decoded: number | boolean | string | Rgb232Triplet;
    let dptId = this.gaToDpt.get(dest) ?? "DPT1.001";
    if (Buffer.isBuffer(value)) {
      const result = this.decodeBuffer(dest, value);
      if (result.ignore) return;
      decoded = result.decoded;
      dptId = result.dptId;
    } else if (typeof value === "number" || typeof value === "boolean") {
      decoded = value;
    } else {
      const nibble = dimObjectToNibble(value);
      decoded = nibble ?? String(value ?? "");
    }
    this.updateCache(dest, decoded, dptId);
  }

  /** Request current bus values (GroupValue_Read) after connect or GA refresh. */
  private scheduleGroupReads(groupAddresses: Iterable<GA>): void {
    const idx = this.gaRoles;
    const gas = [...groupAddresses].sort((a, b) => {
      const pri = (ga: GA) =>
        (idx.get(ga) ?? []).some((r) => READ_PRIORITY_ROLES.has(r.role)) ? 0 : 1;
      return pri(a) - pri(b);
    });

    let delay = 400;
    let scheduled = 0;
    for (const ga of gas) {
      const roles = idx.get(ga) ?? [];
      // Media KNX GAs are command-only. A GroupValue_Read at boot would
      // replay last play/pause or start a dim hold.
      if (
        roles.length > 0 &&
        roles.every(
          (r) => r.deviceType === "media_sonos" || r.deviceType === "media_bluesound"
        )
      ) {
        continue;
      }
      const dp = this.datapoints.get(ga) as { read?: () => void } | undefined;
      if (!dp?.read) continue;
      scheduled++;
      setTimeout(() => {
        try {
          dp.read!();
        } catch (err) {
          logger.warn({ err, ga }, "KNX group read failed");
        }
      }, delay);
      delay += 35;
    }
    if (scheduled > 0) {
      logger.info({ scheduled }, "KNX group reads scheduled");
    }
  }

  private bindDatapoints(
    knx: KnxModule,
    conn: unknown,
    groupAddresses: Iterable<GA>
  ) {
    const idx = this.gaRoles;
    const ordered = [...groupAddresses].sort((a, b) => {
      const score = (ga: GA) =>
        (idx.get(ga) ?? []).some(
          (r) => r.deviceType === "media_sonos" || r.deviceType === "media_bluesound"
        )
          ? 0
          : 1;
      return score(a) - score(b);
    });
    for (const ga of ordered) {
      const dpt = this.gaToDpt.get(ga) ?? "DPT1.001";
      try {
        const dp = new knx.Datapoint({ ga, dpt }, conn as never);
        this.datapoints.set(ga, dp);
      } catch (err) {
        logger.warn({ err, ga }, "Failed to bind datapoint");
      }
    }
  }

  private updateCache(ga: GA, value: number | boolean | string | Rgb232Triplet, dpt?: string) {
    const state: GAState = { ga, value, ts: Date.now(), dpt };
    this.cache.set(ga, state);
    this.emit("stateChanged", state);
  }

  getState(ga: GA): GAState | undefined {
    return this.cache.get(ga);
  }

  getAll(): GAState[] {
    return [...this.cache.values()];
  }

  /** Roles bound to this GA (empty = not in house.json / catalog). */
  getGaRoles(ga: GA): GARole[] {
    return this.gaRoles.get(ga) ?? [];
  }

  /** Push a value to clients without writing the KNX bus (UI echo). */
  reflectLocal(ga: GA, value: number | boolean, role?: string): void {
    const dpt = role ? ROLE_DPT[role] : this.gaToDpt.get(ga);
    this.updateCache(ga, value, dpt);
  }

  /**
   * Write a value onto the bus. The `role` argument selects the DPT.
   * For DPT 232.600 pass an `{ red, green, blue }` object (0–255).
   */
  async write(
    ga: GA,
    role: string,
    value: number | boolean | Rgb232Triplet
  ): Promise<void> {
    const dpt = ROLE_DPT[role] ?? "DPT1.001";

    if (this.simulate) {
      this.noteSelfWrite(ga);
      this.updateCache(ga, value, dpt);
      return;
    }

    const knx = await loadKnxModule();
    const dp = new knx.Datapoint({ ga, dpt }, this.connection as never);
    this.noteSelfWrite(ga);
    await new Promise<void>((resolve, reject) => {
      dp.write(value);
      // knx.js does not expose a promise; we optimistically resolve.
      setTimeout(resolve, 0);
      void reject;
    });
    this.updateCache(ga, value, dpt);
  }

  /**
   * GroupValue_Write met ruwe APDU (geen DPT-encoding). Gebruik voor
   * fabrikant-eigen meerdere bytes op één GA (bijv. 14-byte RGBWWW).
   */
  async writeRaw(ga: GA, data: Buffer, bitlength?: number): Promise<void> {
    const bits = bitlength ?? data.length * 8;

    if (this.simulate) {
      this.noteSelfWrite(ga, data[0]);
      this.updateCache(ga, data.toString("hex"), "RAW");
      return;
    }

    const conn = this.connection as KnxConnection | undefined;
    if (!conn?.writeRaw) {
      throw new Error("KNX writeRaw unavailable (not connected?)");
    }

    this.noteSelfWrite(ga, data[0]);
    await new Promise<void>((resolve, reject) => {
      conn.writeRaw!(ga, data, bits, (err: Error | undefined) => {
        if (err) reject(err);
        else resolve();
      });
    });
    this.updateCache(ga, data.toString("hex"), "RAW");
  }

  /** GroupValue_Read for a bound datapoint (no-op if unbound / simulate). */
  requestRead(ga: GA): void {
    if (this.simulate || this.disabled) return;
    const dp = this.datapoints.get(ga) as { read?: () => void } | undefined;
    try {
      dp?.read?.();
    } catch (err) {
      logger.warn({ err, ga }, "KNX group read failed");
    }
  }

  private noteSelfWrite(ga: GA, byte?: number): void {
    const now = Date.now();
    this.selfWrites.push({ ga, byte, ts: now });
    const cutoff = now - 2000;
    while (this.selfWrites.length && this.selfWrites[0].ts < cutoff) {
      this.selfWrites.shift();
    }
  }

  private isSelfWrite(ga: GA, byte?: number): boolean {
    const now = Date.now();
    return this.selfWrites.some(
      (w) =>
        w.ga === ga &&
        now - w.ts < 900 &&
        (byte === undefined || w.byte === undefined || w.byte === byte)
    );
  }
}

function extractByte(value: unknown): number | undefined {
  if (Buffer.isBuffer(value) && value.length >= 1) return value[0] & 0xff;
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = Math.round(value);
    if (n >= 0 && n <= 255) return n;
  }
  return undefined;
}

/* -------------------- dynamic import of knx ------------------------- */

interface KnxModule {
  Connection: (opts: unknown) => KnxConnection;
  Datapoint: new (opts: { ga: GA; dpt: string }, conn: unknown) => {
    write(v: unknown): void;
    read(): void;
  };
}

interface KnxConnection {
  writeRaw?: (
    grpaddr: GA,
    value: Buffer,
    bitlength: number | undefined,
    callback: (err?: Error) => void
  ) => void;
  Disconnect?: (cb: () => void) => void;
  on?: (e: string, fn: () => void) => void;
}

let knxModulePromise: Promise<KnxModule> | null = null;
async function loadKnxModule(): Promise<KnxModule> {
  if (!knxModulePromise) {
    knxModulePromise = import("knx").then((m) => m as unknown as KnxModule);
  }
  return knxModulePromise;
}

interface DptLib {
  resolve: (id: string) => unknown;
  fromBuffer: (buf: Buffer, dpt: unknown) => unknown;
}

function loadDptLib(): DptLib {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return require("knx/src/dptlib") as DptLib;
}

/** knx.js DPT3.007 → 4-bit nibble (bit3 = increase, bits0–2 = step, 0 = stop). */
function dimObjectToNibble(raw: unknown): number | null {
  if (raw == null || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const stepRaw = o.data ?? o.step;
  if (stepRaw == null && o.decr_incr == null && o.increase == null) return null;
  const increase =
    o.decr_incr != null
      ? Number(o.decr_incr) !== 0
      : o.increase != null
        ? Boolean(o.increase)
        : false;
  const step = Number(stepRaw ?? 0) & 7;
  return (increase ? 8 : 0) | step;
}
