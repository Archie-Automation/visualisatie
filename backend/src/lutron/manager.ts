import net from "node:net";
import { getConfig, updateConfig, walkDevices } from "../config";
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
import { LutronLeapSession, pairWithProcessor } from "./leapClient";
import {
  isLeapTransportPort,
  switchLevelFromRecall,
  type LeapButton,
  type LeapZone,
  type LeapZoneLive
} from "./leapMessages";
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

export type LutronLeapStatus = {
  paired: boolean;
  connected: boolean;
  host: string;
  port: number;
  lastError?: string;
};

export class LutronIntegrationManager {
  private slots: Slot[] = [];
  private leap: LutronLeapSession | null = null;
  private leapHost = "";
  private readonly bus: KnxBus;
  private readonly zones = new Map<number, LeapZoneLive>();
  /** Nieuwe of gewijzigde zonestand, voor de app. */
  onZone?: (zone: LeapZoneLive) => void;

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

  getLeapStatus(): LutronLeapStatus {
    const paired = this.leap != null;
    return {
      paired,
      connected: this.leap?.connected ?? false,
      host: this.leapHost,
      port: 8081,
      lastError: this.leap?.lastError
    };
  }

  /** IP uit de installateur, ook als telnet op 8902 staat en dus niet verbindt. */
  configuredHost(cfg: HouseConfig = getConfig()): string {
    const hl = cfg.lutron;
    return (hl?.telnet?.host ?? hl?.bridgeHost ?? "").trim();
  }

  async pairProcessor(hostOverride?: string): Promise<void> {
    const host = (hostOverride ?? this.configuredHost()).trim();
    if (!host) throw new Error("Vul het IP-adres van de QSX in en sla op.");
    const secrets = await pairWithProcessor(host);
    updateConfig((draft) => {
      draft.lutron = draft.lutron ?? {};
      draft.lutron.telnet = { ...draft.lutron.telnet, host };
      draft.lutron.bridgeHost = host;
      draft.lutron.leap = secrets;
    });
    this.rebuild(getConfig());
  }

  async setSpectrum(zoneId: number, level: number, hue: number, saturation: number): Promise<void> {
    if (!this.leap) {
      throw new Error("HomeWorks QSX is nog niet gekoppeld. Tik op Koppelen en druk daarna de processorknop in.");
    }
    await this.leap.setSpectrum(zoneId, level, hue, saturation);
    this.rememberZone({ id: zoneId, level, hue, saturation });
  }

  async setWhite(zoneId: number, level: number, kelvin: number): Promise<void> {
    if (!this.leap) {
      throw new Error("HomeWorks QSX is nog niet gekoppeld. Tik op Koppelen en druk daarna de processorknop in.");
    }
    await this.leap.setWhite(zoneId, level, kelvin);
    this.rememberZone({ id: zoneId, level, kelvin });
  }

  /** SpectrumTune blijft anders op de laatste kleur, bijvoorbeeld groen. */
  async setSpectrumWhite(zoneId: number, level: number, kelvin: number): Promise<void> {
    if (!this.leap) {
      throw new Error("HomeWorks QSX is nog niet gekoppeld. Tik op Koppelen en druk daarna de processorknop in.");
    }
    await this.leap.setSpectrumWhite(zoneId, level, kelvin);
    this.rememberZone({ id: zoneId, level, kelvin });
  }

  zoneSnapshot(): LeapZoneLive[] {
    return [...this.zones.values()];
  }

  /** Dimmer en RGBW: laatste stand. Een gewone schakelaar gaat naar 100. */
  switchLevel(zoneId: number, on: boolean, fullOn: boolean): number {
    return switchLevelFromRecall(this.zones.get(zoneId)?.recall, on, fullOn);
  }

  private rememberZone(update: {
    id: number;
    level: number;
    hue?: number;
    saturation?: number;
    kelvin?: number;
  }): void {
    const prev = this.zones.get(update.id);
    const level = Math.max(0, Math.min(100, Math.round(update.level)));
    const next: LeapZoneLive = {
      id: update.id,
      level,
      recall: level > 0 ? level : (prev?.recall ?? 0),
      hue: update.hue ?? prev?.hue,
      saturation: update.saturation ?? prev?.saturation,
      kelvin: update.kelvin ?? prev?.kelvin
    };
    this.zones.set(update.id, next);
    this.onZone?.(next);
  }

  listZones(): Promise<LeapZone[]> {
    if (!this.leap) {
      return Promise.reject(
        new Error("HomeWorks QSX is nog niet gekoppeld. Tik op Koppelen en druk daarna de knop op de processor in.")
      );
    }
    return this.leap.listZones();
  }

  listButtons(): Promise<LeapButton[]> {
    if (!this.leap) return Promise.resolve([]);
    return this.leap.listButtons();
  }

  private leapDebounce = new Map<string, number>();

  /** Keypad-druk van LEAP. integrationId in de mapping is het knop-id. */
  private onLeapButton(press: { id: number; action: number }): void {
    const cfg = getConfig();
    const maps: { source: string; map: LutronButtonToKnxMapping }[] = [];
    for (const map of cfg.lutron?.buttonToKnx ?? []) {
      maps.push({ source: "QSX", map });
    }
    walkDevices(cfg, (d) => {
      if (d.type !== "lutron_homeworks") return;
      for (const map of d.lutronHomeworks.buttonToKnx ?? []) {
        maps.push({ source: d.name, map });
      }
    });
    for (const { source, map } of maps) {
      if (map.integrationId !== press.id) continue;
      if (map.actionNumber != null && map.actionNumber !== press.action) continue;
      const key = `${map.id}:${press.id}:${press.action}`;
      const now = Date.now();
      const prev = this.leapDebounce.get(key) ?? 0;
      if (now - prev < DEBOUNCE_MS) continue;
      this.leapDebounce.set(key, now);
      void this.fireButtonMapping(source, map).catch((err) => {
        logger.warn({ err, button: press.id, map: map.id }, "QSX-knop → KNX mislukt");
      });
    }
  }

  rebuild(cfg: HouseConfig): void {
    this.leap?.stop();
    this.leap = null;
    this.stopAll();

    const hl = cfg.lutron;
    this.leapHost = this.configuredHost(cfg);
    const leap = hl?.leap;
    if (
      this.leapHost &&
      leap?.privateKey?.includes("PRIVATE KEY") &&
      leap.certificate?.includes("BEGIN CERTIFICATE")
    ) {
      this.leap = new LutronLeapSession(this.leapHost, {
        paired: true,
        certificate: leap.certificate,
        privateKey: leap.privateKey,
        rootCertificate: leap.rootCertificate ?? ""
      });
      this.leap.onButton = (press) => this.onLeapButton(press);
      this.leap.onZoneLevel = (level) => this.rememberZone(level);
      this.leap.start();
    }

    logger.info({ leap: this.leap != null }, "Lutron integratie herbouwd");
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

  async setHomeworksOutputLevel(binding: LutronLoadOutputBinding, percent: number): Promise<void> {
    if (this.leap) {
      await this.leap.setLevel(binding.integrationId, percent, binding.fadeSeconds);
      this.rememberZone({ id: binding.integrationId, level: percent });
      return;
    }
    this.assertTelnetPath();
    const s = this.pickSlot(binding);
    this.sendLine(
      s,
      buildOutputSetLevel(binding.integrationId, percent, binding.fadeSeconds, 0)
    );
  }

  async shadeHomeworksRaise(binding: LutronLoadOutputBinding): Promise<void> {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    if (this.leap) {
      await this.leap.zoneCommand(binding.integrationId, "Raise");
      return;
    }
    this.assertTelnetPath();
    this.sendLine(this.pickSlot(binding), buildOutputRaise(binding.integrationId));
  }

  async shadeHomeworksLower(binding: LutronLoadOutputBinding): Promise<void> {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    if (this.leap) {
      await this.leap.zoneCommand(binding.integrationId, "Lower");
      return;
    }
    this.assertTelnetPath();
    this.sendLine(this.pickSlot(binding), buildOutputLower(binding.integrationId));
  }

  async shadeHomeworksStop(binding: LutronLoadOutputBinding): Promise<void> {
    if (binding.loadType !== "shade") throw new Error("Lutron-load is geen shade");
    if (this.leap) {
      await this.leap.zoneCommand(binding.integrationId, "Stop");
      return;
    }
    this.assertTelnetPath();
    this.sendLine(this.pickSlot(binding), buildOutputStop(binding.integrationId));
  }

  /** Stel lamelhoek (tilt) in via een apart Lutron output integration ID. */
  async shadeHomeworksSetSlats(
    binding: LutronLoadOutputBinding,
    slatIntegrationId: number,
    percent: number
  ): Promise<void> {
    const slatBinding: LutronLoadOutputBinding = {
      ...binding,
      integrationId: slatIntegrationId,
      loadType: "shade"
    };
    if (this.leap) {
      const zone = slatIntegrationId >= 1 ? slatIntegrationId : binding.integrationId;
      await this.leap.setTilt(zone, percent);
      return;
    }
    this.assertTelnetPath();
    this.sendLine(
      this.pickSlot(slatBinding),
      buildOutputSetLevel(slatIntegrationId, percent, binding.fadeSeconds, 0)
    );
  }

  /** Telnet op 8902 lijkt verbonden maar de QSX voert #OUTPUT daar niet uit. */
  private assertTelnetPath(): void {
    const port = getConfig().lutron?.telnet?.port;
    if (isLeapTransportPort(port)) {
      throw new Error(
        "HomeWorks QSX praat niet via telnet op deze poort. Tik op Koppelen en druk daarna de knop op de processor in."
      );
    }
  }
}
