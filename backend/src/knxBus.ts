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
  uint16: "DPT7.001",   // 0..65535 unsigned int (e.g. day counter)
  signed_byte: "DPT6.001",   // −128..127 signed byte
  signed_2byte: "DPT8.001",  // 2-byte signed int
  uint32: "DPT12.001",       // 0..4 294 967 295
  int32: "DPT13.001",        // signed 32-bit int
  float4byte: "DPT14.019",   // 4-byte IEEE-754 float (DPT14.x)
  scene_number: "DPT17.001", // 0..63 scene number
  flame: "DPT5.010",
  flame_status: "DPT5.010",
  ac_mode: "DPT5.010",
  fan_speed: "DPT5.010",

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
export class KnxBus extends EventEmitter {
  private readonly cache = new Map<GA, GAState>();
  private readonly gaToDpt = new Map<GA, string>();
  private connection: unknown;
  private readonly simulate: boolean;
  /** When true the bus is administratively disabled; connect() is a no-op. */
  private disabled: boolean;
  private readonly datapoints = new Map<GA, unknown>();
  private busConnected = false;

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

    for (const ga of wanted) {
      if (this.datapoints.has(ga)) continue;
      const dpt = this.gaToDpt.get(ga) ?? "DPT1.001";
      try {
        const dp = new knx.Datapoint({ ga, dpt }, this.connection as never);
        this.datapoints.set(ga, dp);
      } catch (err) {
        logger.warn({ err, ga }, "Failed to bind datapoint on refresh");
      }
    }

    logger.info({ count: this.datapoints.size }, "KNX group addresses refreshed");
  }

  private rebuildGaDptMap(): void {
    this.gaToDpt.clear();
    const idx = buildGAIndex(getConfig());
    for (const [ga, roles] of idx) {
      this.gaToDpt.set(ga, this.pickDptForGa(roles));
    }
  }

  private pickDptForGa(roles: GARole[]): string {
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

  private onBusTelegram(dest: GA, value: unknown): void {
    const dptId = this.gaToDpt.get(dest) ?? "DPT1.001";
    let decoded: number | boolean | string | Rgb232Triplet;
    if (Buffer.isBuffer(value)) {
      try {
        const DPTLib = loadDptLib();
        const dpt = DPTLib.resolve(dptId);
        const raw = DPTLib.fromBuffer(value, dpt);
        decoded = this.normalizeDecoded(raw);
      } catch (err) {
        logger.warn({ err, dest, dptId }, "KNX telegram decode failed");
        const buf = value as Buffer;
        decoded = buf.length > 0 ? Boolean(buf[0] & 0x01) : false;
      }
    } else if (typeof value === "number" || typeof value === "boolean") {
      decoded = value;
    } else {
      decoded = String(value ?? "");
    }
    this.updateCache(dest, decoded, dptId);
  }

  private bindDatapoints(
    knx: KnxModule,
    conn: unknown,
    groupAddresses: Iterable<GA>
  ) {
    for (const ga of groupAddresses) {
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
      // Simulate a round-trip: the status GA will also echo.
      this.updateCache(ga, value, dpt);
      return;
    }

    const knx = await loadKnxModule();
    const dp = new knx.Datapoint({ ga, dpt }, this.connection as never);
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
      this.updateCache(ga, data.toString("hex"), "RAW");
      return;
    }

    const conn = this.connection as KnxConnection | undefined;
    if (!conn?.writeRaw) {
      throw new Error("KNX writeRaw unavailable (not connected?)");
    }

    await new Promise<void>((resolve, reject) => {
      conn.writeRaw!(ga, data, bits, (err: Error | undefined) => {
        if (err) reject(err);
        else resolve();
      });
    });
    this.updateCache(ga, data.toString("hex"), "RAW");
  }
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
