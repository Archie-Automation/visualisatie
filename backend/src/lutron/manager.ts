import net from "node:net";
import { getConfig, walkDevices } from "../config";
import { logger } from "../logger";
import type { KnxBus } from "../knxBus";
import type {
  HouseConfig,
  LutronButtonToKnxMapping,
  LutronHomeworksDevice,
  LutronLoadOutputBinding,
  LutronTelnetConfig
} from "../types";
import { executeLutronToKnx, logLutronKnx } from "./knxBridge";
import {
  buildOutputLower,
  buildOutputRaise,
  buildOutputSetLevel,
  buildOutputStop
} from "./outputCommands";
import { HOUSE_LUTRON_SLOT_ID } from "./resolve";

export type LutronClientStatus = {
  deviceId: string;
  name: string;
  host: string;
  port: number;
  connected: boolean;
  loggedIn: boolean;
  lastError?: string;
  lastTelnetLine?: string;
};

type Slot = {
  slotId: string;
  displayName: string;
  telnet?: LutronTelnetConfig;
  bridgeHost?: string;
  buttonToKnx: LutronButtonToKnxMapping[];
  socket?: net.Socket;
  connected: boolean;
  loggedIn: boolean;
  loginSent: boolean;
  passwordSent: boolean;
  postLoginSent: boolean;
  lastError?: string;
  lastTelnetLine?: string;
  debounce: Map<string, number>;
  reconnectTimer?: NodeJS.Timeout;
  buffer: string;
};

const DEVICE_LINE =
  /^[~#]DEVICE,(\d+),(\d+),(\d+)(?:,([^,\r\n]*))?(?:,.*)?$/;

const DEBOUNCE_MS = 450;

export class LutronIntegrationManager {
  private slots: Slot[] = [];
  private readonly bus: KnxBus;

  constructor(bus: KnxBus) {
    this.bus = bus;
  }

  getStatus(): LutronClientStatus[] {
    return this.slots.map((s) => {
      const host = (s.telnet?.host ?? s.bridgeHost ?? "").trim();
      return {
        deviceId: s.slotId,
        name: s.displayName,
        host,
        port: s.telnet?.port ?? 23,
        connected: s.connected,
        loggedIn: s.loggedIn,
        lastError: s.lastError,
        lastTelnetLine: s.lastTelnetLine
      };
    });
  }

  rebuild(cfg: HouseConfig): void {
    this.stopAll();

    const hl = cfg.lutron;
    if (hl) {
      const tel = hl.telnet;
      const host = (tel?.host ?? hl.bridgeHost ?? "").trim();
      if (tel?.enabled && host) {
        this.slots.push(this.emptySlot({
          slotId: HOUSE_LUTRON_SLOT_ID,
          displayName: "Lutron QSX/QS Processor",
          telnet: tel,
          bridgeHost: hl.bridgeHost,
          buttonToKnx: hl.buttonToKnx ?? []
        }));
      }
    }

    walkDevices(cfg, (d) => {
      if (d.type !== "lutron_homeworks") return;
      const lh = d.lutronHomeworks;
      const tel = lh.telnet;
      const host = (tel?.host ?? lh.bridgeHost ?? "").trim();
      if (!tel?.enabled || !host) return;
      if (this.slots.some((s) => s.slotId === d.id)) return;
      this.slots.push(
        this.emptySlot({
          slotId: d.id,
          displayName: d.name,
          telnet: tel,
          bridgeHost: lh.bridgeHost,
          buttonToKnx: lh.buttonToKnx ?? []
        })
      );
    });

    for (const s of this.slots) {
      this.scheduleConnect(s, 0);
    }
    logger.info({ clients: this.slots.length }, "Lutron integratie herbouwd");
  }

  reconnect(): void {
    const cfg = getConfig();
    this.rebuild(cfg);
  }

  /**
   * Handmatig een mapping uitvoeren (app “Test” of automatisering).
   * `deviceId` = `house` voor project-mappings, anders id van `lutron_homeworks`.
   */
  async fireMapping(deviceId: string, mappingId: string): Promise<void> {
    const cfg = getConfig();
    let maps: LutronButtonToKnxMapping[] | undefined;
    let label = "Lutron";

    if (deviceId === HOUSE_LUTRON_SLOT_ID) {
      maps = cfg.lutron?.buttonToKnx;
      label = "Lutron Homeworks";
    } else {
      let dev: LutronHomeworksDevice | undefined;
      walkDevices(cfg, (d) => {
        if (d.type === "lutron_homeworks" && d.id === deviceId) dev = d;
      });
      if (!dev) throw new Error("unknown lutron device");
      maps = dev.lutronHomeworks.buttonToKnx;
      label = dev.name;
    }

    const m = (maps ?? []).find((x) => x.id === mappingId);
    if (!m) throw new Error("unknown lutron mapping");
    logLutronKnx(label, m.label, m.knx);
    await executeLutronToKnx(this.bus, m.knx);
  }

  stopAll(): void {
    for (const s of this.slots) {
      if (s.reconnectTimer) {
        clearTimeout(s.reconnectTimer);
        s.reconnectTimer = undefined;
      }
      if (s.socket) {
        s.socket.removeAllListeners();
        s.socket.destroy();
      }
      s.socket = undefined;
    }
    this.slots = [];
  }

  private emptySlot(partial: {
    slotId: string;
    displayName: string;
    telnet?: LutronTelnetConfig;
    bridgeHost?: string;
    buttonToKnx: LutronButtonToKnxMapping[];
  }): Slot {
    return {
      ...partial,
      connected: false,
      loggedIn: false,
      loginSent: false,
      passwordSent: false,
      postLoginSent: false,
      debounce: new Map(),
      buffer: ""
    };
  }

  private pickSlot(binding: LutronLoadOutputBinding): Slot {
    const id = binding.homeworksDeviceId?.trim();
    if (id) {
      const s = this.slots.find((x) => x.slotId === id);
      if (s) return s;
    }
    const house = this.slots.find((x) => x.slotId === HOUSE_LUTRON_SLOT_ID);
    if (house) return house;
    if (this.slots.length === 1) return this.slots[0];
    throw new Error("Lutron-gateway niet geconfigureerd of niet verbonden");
  }

  private scheduleConnect(s: Slot, delayMs: number): void {
    if (s.reconnectTimer) clearTimeout(s.reconnectTimer);
    s.reconnectTimer = setTimeout(() => {
      s.reconnectTimer = undefined;
      void this.connect(s);
    }, delayMs);
  }

  private async connect(s: Slot): Promise<void> {
    const host = (s.telnet?.host ?? s.bridgeHost ?? "").trim();
    if (!host) return;
    const port = s.telnet?.port ?? 23;

    s.socket?.destroy();
    s.buffer = "";
    s.connected = false;
    s.loggedIn = false;
    s.loginSent = false;
    s.passwordSent = false;
    s.postLoginSent = false;

    const sock = new net.Socket();
    s.socket = sock;

    sock.setTimeout(120_000);

    sock.on("error", (err) => {
      s.lastError = (err as Error).message;
      logger.warn({ err, slot: s.slotId, host, port }, "Lutron telnet fout");
    });

    sock.on("close", () => {
      s.connected = false;
      s.loggedIn = false;
      s.socket = undefined;
      if (!this.slots.includes(s)) return;
      logger.info({ slot: s.slotId }, "Lutron telnet gesloten — herverbinding over 10s");
      this.scheduleConnect(s, 10_000);
    });

    sock.on("timeout", () => {
      s.lastError = "socket timeout";
      sock.destroy();
    });

    sock.connect(port, host, () => {
      s.connected = true;
      s.lastError = undefined;
      logger.info({ slot: s.slotId, host, port }, "Lutron telnet verbonden");
      if (!s.telnet?.username?.trim()) {
        s.loggedIn = true;
        setImmediate(() => this.sendPostLogin(s));
      }
    });

    sock.on("data", (chunk) => this.onData(s, chunk));
  }

  private onData(s: Slot, chunk: Buffer): void {
    s.buffer += chunk.toString("utf8");
    const parts = s.buffer.split(/\r?\n/);
    s.buffer = parts.pop() ?? "";
    for (const raw of parts) {
      const line = raw.trim();
      if (line.length === 0) continue;
      s.lastTelnetLine = line.length > 240 ? `${line.slice(0, 240)}…` : line;
      this.handleLine(s, line);
    }
  }

  private handleLine(s: Slot, line: string): void {
    const tel = s.telnet;
    const lower = line.toLowerCase();

    if (!s.loggedIn && tel?.username?.trim()) {
      if (!s.loginSent && lower.includes("login")) {
        s.socket?.write(`${tel.username!.trim()}\r\n`);
        s.loginSent = true;
        return;
      }
      if (
        s.loginSent &&
        !s.passwordSent &&
        (lower.includes("password") || lower.includes("passcode"))
      ) {
        const pw = tel.password ?? "";
        s.socket?.write(`${pw}\r\n`);
        s.passwordSent = true;
        s.loggedIn = true;
        setImmediate(() => this.sendPostLogin(s));
        return;
      }
    }

    const m = DEVICE_LINE.exec(line);
    if (!m) return;

    const integrationId = Number(m[1]);
    const component = Number(m[2]);
    const action = Number(m[3]);

    for (const map of s.buttonToKnx) {
      if (map.integrationId !== integrationId) continue;
      if (map.componentNumber !== component) continue;
      if (map.actionNumber != null && map.actionNumber !== action) continue;

      const key = `${map.id}:${integrationId}:${component}:${action}`;
      const now = Date.now();
      const prev = s.debounce.get(key) ?? 0;
      if (now - prev < DEBOUNCE_MS) continue;
      s.debounce.set(key, now);

      void this.fireButtonMapping(s.displayName, map).catch((err) => {
        logger.warn({ err, slot: s.slotId, map: map.id }, "Lutron→KNX mapping mislukt");
      });
    }
  }

  private sendPostLogin(s: Slot): void {
    if (!s.socket || s.postLoginSent || !s.loggedIn) return;
    const tel = s.telnet;
    const cmds =
      tel?.postLoginCommands && tel.postLoginCommands.length > 0
        ? tel.postLoginCommands
        : ["#MONITORING,3,1"];
    for (const c of cmds) {
      const line = c.endsWith("\n") ? c : `${c}\r\n`;
      s.socket.write(line);
    }
    s.postLoginSent = true;
    logger.info({ slot: s.slotId, cmds }, "Lutron post-login commando’s verzonden");
  }

  private async fireButtonMapping(
    sourceName: string,
    map: LutronButtonToKnxMapping
  ): Promise<void> {
    logLutronKnx(sourceName, map.label, map.knx);
    await executeLutronToKnx(this.bus, map.knx);
  }

  private sendLine(s: Slot, line: string): void {
    if (!s.socket || !s.connected) {
      throw new Error(`Lutron niet verbonden (${s.slotId})`);
    }
    if (!s.loggedIn) throw new Error("Lutron telnet nog niet ingelogd");
    const payload = line.endsWith("\r\n") ? line : `${line}\r\n`;
    s.socket.write(payload);
    logger.info({ slot: s.slotId, line: line.slice(0, 160) }, "Lutron telnet commando");
  }

  setHomeworksOutputLevel(binding: LutronLoadOutputBinding, percent: number): void {
    const s = this.pickSlot(binding);
    this.sendLine(
      s,
      buildOutputSetLevel(binding.integrationId, percent, binding.fadeSeconds, 0)
    );
  }

  shadeHomeworksRaise(binding: LutronLoadOutputBinding): void {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    this.sendLine(this.pickSlot(binding), buildOutputRaise(binding.integrationId));
  }

  shadeHomeworksLower(binding: LutronLoadOutputBinding): void {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    this.sendLine(this.pickSlot(binding), buildOutputLower(binding.integrationId));
  }

  shadeHomeworksStop(binding: LutronLoadOutputBinding): void {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    this.sendLine(this.pickSlot(binding), buildOutputStop(binding.integrationId));
  }

  /** Stel lamelhoek (tilt) in via een apart Lutron output integration ID. */
  shadeHomeworksSetSlats(
    binding: LutronLoadOutputBinding,
    slatIntegrationId: number,
    percent: number
  ): void {
    const slatBinding: LutronLoadOutputBinding = {
      ...binding,
      integrationId: slatIntegrationId,
      loadType: "shade"
    };
    this.sendLine(
      this.pickSlot(slatBinding),
      buildOutputSetLevel(slatIntegrationId, percent, binding.fadeSeconds, 0)
    );
  }
}
