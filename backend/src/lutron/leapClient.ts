import tls from "node:tls";
import forge from "node-forge";
import { logger } from "../logger";
import { LAP_CA_PEM, LAP_CERT_PEM, LAP_KEY_PEM, LUTRON_ROOT_CA_PEM } from "./lapCerts";
import {
  LEAP_PAIR_PORT,
  LEAP_PORT,
  type LeapButton,
  type LeapButtonPress,
  type LeapSecrets,
  type LeapZone,
  buildGoToLevel,
  buildGoToTilt,
  buildPairRequest,
  buildPingResponse,
  buildReadRequest,
  buildSpectrum,
  buildSubscribeRequest,
  buildWhite,
  buildZoneCommand,
  encodeLeap,
  headerUrl,
  leapErrorMessage,
  collectDefinedButtons,
  collectDevices,
  collectHrefs,
  deviceMayHaveButtons,
  parseButtonEvents,
  parsePairingMessage,
  parseZoneList
} from "./leapMessages";

const PAIR_TIMEOUT_MS = 150_000;
const REQUEST_TIMEOUT_MS = 8_000;

export function generatePairingMaterial(): { csrPem: string; keyPem: string } {
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const csr = forge.pki.createCertificationRequest();
  csr.publicKey = keys.publicKey;
  csr.setSubject([{ name: "commonName", value: "ArchieOS" }]);
  csr.sign(keys.privateKey, forge.md.sha256.create());
  return {
    csrPem: forge.pki.certificationRequestToPem(csr).replace(/\r\n/g, "\n"),
    keyPem: forge.pki.privateKeyToPem(keys.privateKey)
  };
}

/**
 * Eenmalig op poort 8083.
 * De processor stuurt eerst statussen. Pas als de knop is ingedrukt
 * (PhysicalAccess) mag de CSR eruit. CommandType is CSR, niet Execute.
 * QSX verifieert met het Lutron-rootcertificaat en TLS 1.2.
 */
export async function pairWithProcessor(host: string): Promise<LeapSecrets> {
  const target = host.trim();
  if (!target) throw new Error("Vul het IP-adres van de QSX in en sla op.");
  const { csrPem, keyPem } = generatePairingMaterial();
  try {
    return await runPairing(target, csrPem, keyPem, true);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (/knop|certificaat|geweigerd|CSR/i.test(message)) throw err;
    logger.warn({ err, host: target }, "QSX-koppeling met Lutron-root mislukt, opnieuw zonder CA-check");
    return runPairing(target, csrPem, keyPem, false);
  }
}

function runPairing(
  target: string,
  csrPem: string,
  keyPem: string,
  verifyServer: boolean
): Promise<LeapSecrets> {
  return new Promise((resolve, reject) => {
    const socket = tls.connect({
      host: target,
      port: LEAP_PAIR_PORT,
      cert: LAP_CERT_PEM,
      key: LAP_KEY_PEM,
      ca: verifyServer ? `${LAP_CA_PEM}\n${LUTRON_ROOT_CA_PEM}` : undefined,
      rejectUnauthorized: verifyServer,
      minVersion: "TLSv1.2",
      maxVersion: "TLSv1.2",
      servername: "",
      checkServerIdentity: () => undefined
    });
    let settled = false;
    let csrSent = false;
    const finish = (err: Error | null, secrets?: LeapSecrets) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      if (err || !secrets) reject(err ?? new Error("Koppelen mislukt"));
      else resolve(secrets);
    };
    const timer = setTimeout(() => {
      finish(
        new Error(
          csrSent
            ? "De processor tekende het certificaat niet. Houd de knop ingedrukt tot het lampje stopt met knipperen en koppel opnieuw."
            : "De processor wacht op de knop. Tik op Koppelen en druk daarna de knop op de QSX in tot het lampje knippert."
        )
      );
    }, PAIR_TIMEOUT_MS);

    socket.once("error", (err) => {
      finish(new Error(`Koppelen mislukt (${target}:${LEAP_PAIR_PORT}): ${err.message}`));
    });
    socket.once("secureConnect", () => {
      logger.info({ host: target, port: LEAP_PAIR_PORT, verifyServer }, "QSX-koppeling open, wacht op de knop");
    });
    const take = (msg: unknown) => {
      const parsed = parsePairingMessage(msg);
      if (parsed.kind === "waiting") {
        logger.info({ host: target }, "QSX wacht nog op de knop");
        return;
      }
      if (parsed.kind === "ready") {
        if (csrSent) return;
        csrSent = true;
        logger.info({ host: target }, "QSX-knop gezien, CSR wordt gestuurd");
        socket.write(encodeLeap(buildPairRequest(csrPem)));
        return;
      }
      if (parsed.kind === "error") {
        finish(new Error(parsed.message));
        return;
      }
      if (parsed.kind === "cert") {
        const returned = parsed.rootCertificate.includes("BEGIN CERTIFICATE")
          ? parsed.rootCertificate
          : "";
        finish(null, {
          paired: true,
          certificate: parsed.certificate,
          privateKey: keyPem,
          rootCertificate: [returned, LUTRON_ROOT_CA_PEM].filter(Boolean).join("\n")
        });
        return;
      }
      logger.info({ host: target, keys: messageKeys(msg) }, "QSX-koppelbericht genegeerd");
    };
    readLeapLines(socket, take);
  });
}

function messageKeys(msg: unknown): string[] {
  if (!msg || typeof msg !== "object") return [];
  const root = msg as Record<string, unknown>;
  const header = (root.Header ?? {}) as Record<string, unknown>;
  return [String(root.CommuniqueType ?? header.RequestType ?? ""), String(header.StatusCode ?? ""), String(header.Url ?? "")];
}

type Pending = {
  resolve: (msg: unknown) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
};

/** Blijvende LEAP-sessie naar poort 8081 met het gekoppelde certificaat. */
export class LutronLeapSession {
  connected = false;
  lastError?: string;
  /** Keypad-druk nadat het abonnement staat. De eerste seconden na verbinden worden genegeerd. */
  onButton?: (press: LeapButtonPress) => void;
  private buttonsReadyAt = Number.POSITIVE_INFINITY;
  private socket?: tls.TLSSocket;
  private buffer = "";
  private pending = new Map<string, Pending>();
  private reconnectTimer?: NodeJS.Timeout;
  private stopped = false;
  private relaxedTls = false;
  private immediateRetry = false;
  private buttonLoad: Promise<LeapButton[]> | null = null;
  /** `/button` gaf niets. Dan is een bulk-abonnement meestal ook leeg. */
  private subscribeButtonsOneByOne = false;

  constructor(
    private readonly host: string,
    private readonly secrets: LeapSecrets
  ) {}

  start(): void {
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = undefined;
    this.failPending(new Error("QSX-verbinding gesloten"));
    this.socket?.destroy();
    this.socket = undefined;
    this.connected = false;
  }

  async setLevel(zoneId: number, percent: number, fadeSeconds?: number): Promise<void> {
    const msg = buildGoToLevel(zoneId, percent, fadeSeconds);
    await this.request(msg, `/zone/${zoneId}/commandprocessor`);
  }

  async zoneCommand(zoneId: number, command: "Raise" | "Lower" | "Stop"): Promise<void> {
    await this.request(buildZoneCommand(zoneId, command), `/zone/${zoneId}/commandprocessor`);
  }

  async setTilt(zoneId: number, percent: number): Promise<void> {
    await this.request(buildGoToTilt(zoneId, percent), `/zone/${zoneId}/commandprocessor`);
  }

  /** Clear Connect Type X kleurzone op de QSX. */
  async setSpectrum(zoneId: number, level: number, hue: number, saturation: number): Promise<void> {
    await this.request(
      buildSpectrum(zoneId, level, hue, saturation),
      `/zone/${zoneId}/commandprocessor`
    );
  }

  async setWhite(zoneId: number, level: number, kelvin: number): Promise<void> {
    await this.request(buildWhite(zoneId, level, kelvin), `/zone/${zoneId}/commandprocessor`);
  }

  async listZones(): Promise<LeapZone[]> {
    await this.waitConnected(REQUEST_TIMEOUT_MS);
    const zoneMsg = await this.readOptional("/zone");
    const areaMsg = await this.readOptional("/area");
    let zones = parseZoneList(zoneMsg ?? {}, areaMsg ?? {});
    if (zones.length === 0 && areaMsg) {
      const hrefs = hrefList(areaMsg, "Areas", "AreaSummaries");
      const parts: unknown[] = [];
      for (const href of hrefs) {
        const part = await this.readOptional(`${href}/associatedzone`);
        if (part) parts.push(part);
      }
      if (parts.length > 0) zones = parseZoneList(mergeZoneMessages(parts), areaMsg);
    }
    return zones;
  }

  async listButtons(): Promise<LeapButton[]> {
    if (!this.buttonLoad) {
      this.buttonLoad = this.discoverButtons().catch((err) => {
        this.buttonLoad = null;
        throw err;
      });
    }
    return this.buttonLoad;
  }

  /**
   * Keypad-knoppen staan niet in de zonelijst. `/button` weigert een QSX vaak;
   * dan zitten ze op het control station van de schakelaar.
   */
  private async discoverButtons(): Promise<LeapButton[]> {
    await this.waitConnected(REQUEST_TIMEOUT_MS);
    const direct = collectDefinedButtons(await this.readOptional("/button"));
    if (direct.length > 0) {
      this.subscribeButtonsOneByOne = false;
      return direct;
    }
    this.subscribeButtonsOneByOne = true;

    const found = new Map<number, LeapButton>();
    const take = (buttons: LeapButton[]) => {
      for (const button of buttons) found.set(button.id, button);
    };

    const areaMsg = await this.readOptional("/area");
    for (const area of collectHrefs(areaMsg, "area")) {
      if (this.stopped || !this.connected) break;
      const stations = await this.readOptional(`${area}/associatedcontrolstation`);
      await this.readStationButtons(stations, take);
    }
    if (found.size === 0) {
      const devices = collectDevices(await this.readOptional("/device")).filter((device) =>
        deviceMayHaveButtons(device.deviceType)
      );
      for (const device of devices) {
        if (this.stopped || !this.connected) break;
        take(await this.buttonsOnDevice(device.href, device.name));
      }
    }
    return [...found.values()].sort((a, b) => a.id - b.id);
  }

  private async readStationButtons(
    msg: unknown,
    take: (buttons: LeapButton[]) => void
  ): Promise<void> {
    take(collectDefinedButtons(msg));
    for (const station of collectHrefs(msg, "controlstation")) {
      if (this.stopped || !this.connected) return;
      const full = await this.readOptional(station);
      const name = stationName(full);
      take(collectDefinedButtons(full, name));
      for (const device of collectDevices(full)) {
        if (this.stopped || !this.connected) return;
        take(await this.buttonsOnDevice(device.href, device.name || name));
      }
    }
  }

  private async buttonsOnDevice(href: string, deviceName: string): Promise<LeapButton[]> {
    const full = await this.readOptional(href);
    const defined = collectDefinedButtons(full, deviceName);
    if (defined.length > 0) return defined;
    const out: LeapButton[] = [];
    const groups = collectHrefs(full, "buttongroup");
    const hrefs = new Set<string>(collectHrefs(full, "button"));
    for (const group of groups) {
      if (this.stopped || !this.connected) break;
      const groupMsg = await this.readOptional(group);
      const named = collectDefinedButtons(groupMsg, deviceName);
      if (named.length > 0) out.push(...named);
      else for (const href of collectHrefs(groupMsg, "button")) hrefs.add(href);
    }
    if (out.length === 0 && hrefs.size === 0) {
      const child = await this.readOptional(`${href}/button`);
      const named = collectDefinedButtons(child, deviceName);
      if (named.length > 0) return named;
      for (const buttonHref of collectHrefs(child, "button")) hrefs.add(buttonHref);
    }
    for (const buttonHref of hrefs) {
      if (this.stopped || !this.connected) break;
      out.push(...collectDefinedButtons(await this.readOptional(buttonHref), deviceName));
    }
    return out;
  }

  private async subscribeButtons(): Promise<void> {
    const buttons = await this.listButtons().catch(() => [] as LeapButton[]);
    logger.info(
      { count: buttons.length, perButton: this.subscribeButtonsOneByOne },
      "QSX-knoppen"
    );
    if (!this.subscribeButtonsOneByOne && (await this.subscribe("/button/status"))) return;
    for (const button of buttons) {
      if (this.stopped || !this.connected) return;
      await this.subscribe(`/button/${button.id}/status`);
    }
  }

  private async subscribe(url: string): Promise<boolean> {
    try {
      await this.request(buildSubscribeRequest(url), url);
      return true;
    } catch (err) {
      logger.info({ url, err }, "QSX-knopabonnement niet ondersteund");
      return false;
    }
  }

  /** QSX wijst /zone of /area soms af. Dat mag de rest van de lijst niet laten falen. */
  private async readOptional(url: string): Promise<unknown | null> {
    try {
      return await this.request(buildReadRequest(url), url);
    } catch (err) {
      logger.info({ url, err }, "QSX-leesverzoek niet ondersteund");
      return null;
    }
  }

  private waitConnected(ms: number): Promise<void> {
    if (this.connected) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(this.lastError ?? "QSX is niet verbonden"));
      }, ms);
      const tick = () => {
        if (this.connected) {
          clearTimeout(timer);
          resolve();
          return;
        }
        if (this.stopped) {
          clearTimeout(timer);
          reject(new Error("QSX-verbinding gesloten"));
          return;
        }
        setTimeout(tick, 200);
      };
      tick();
    });
  }

  private connect(): void {
    if (this.stopped) return;
    this.socket?.destroy();
    this.buffer = "";
    this.connected = false;
    const ca = [this.secrets.rootCertificate, LUTRON_ROOT_CA_PEM]
      .filter((pem) => pem.includes("BEGIN CERTIFICATE"))
      .join("\n");
    const socket = tls.connect({
      host: this.host,
      port: LEAP_PORT,
      ca: ca || undefined,
      cert: this.secrets.certificate,
      key: this.secrets.privateKey,
      rejectUnauthorized: !this.relaxedTls,
      minVersion: "TLSv1.2",
      maxVersion: "TLSv1.2",
      servername: "",
      checkServerIdentity: () => undefined
    });
    this.socket = socket;
    socket.setKeepAlive(true, 30_000);
    socket.once("secureConnect", () => {
      this.connected = true;
      this.lastError = undefined;
      this.buttonsReadyAt = Date.now() + 2_000;
      this.buttonLoad = null;
      this.subscribeButtonsOneByOne = false;
      logger.info({ host: this.host, port: LEAP_PORT }, "QSX LEAP verbonden");
      void this.subscribeButtons();
    });
    socket.on("error", (err) => {
      this.lastError = err.message;
      this.connected = false;
      if (!this.relaxedTls && /cert|handshake|alert|unknown/i.test(err.message)) {
        this.relaxedTls = true;
        this.immediateRetry = true;
      }
      logger.warn({ err, host: this.host }, "QSX LEAP fout");
    });
    socket.on("close", () => {
      this.connected = false;
      this.failPending(new Error("QSX-verbinding gesloten"));
      if (this.socket === socket) this.socket = undefined;
      if (this.stopped) return;
      if (this.immediateRetry) {
        this.immediateRetry = false;
        this.connect();
        return;
      }
      logger.info({ host: this.host }, "QSX LEAP gesloten — herverbinding over 10s");
      this.reconnectTimer = setTimeout(() => this.connect(), 10_000);
    });
    socket.on("data", (chunk: Buffer) => this.onData(chunk));
  }

  private onData(chunk: Buffer): void {
    this.buffer += chunk.toString("utf8");
    let idx = this.buffer.indexOf("\n");
    while (idx >= 0) {
      const line = this.buffer.slice(0, idx).replace(/\r$/, "").trim();
      this.buffer = this.buffer.slice(idx + 1);
      idx = this.buffer.indexOf("\n");
      if (!line) continue;
      let msg: unknown;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      this.dispatch(msg);
    }
  }

  private dispatch(msg: unknown): void {
    const ping = buildPingResponse(msg);
    if (ping && this.socket && this.connected) {
      this.socket.write(encodeLeap(ping));
      return;
    }
    if (Date.now() >= this.buttonsReadyAt) {
      for (const press of parseButtonEvents(msg)) this.onButton?.(press);
    }
    const url = headerUrl(msg);
    for (const [key, pending] of this.pending) {
      if (url === key || url.startsWith(`${key}?`) || url.startsWith(`${key}/`)) {
        clearTimeout(pending.timer);
        this.pending.delete(key);
        const err = leapErrorMessage(msg);
        if (err) pending.reject(new Error(err));
        else pending.resolve(msg);
        return;
      }
    }
  }

  private request(message: object, url: string): Promise<unknown> {
    if (!this.socket || !this.connected) {
      return Promise.reject(new Error(this.lastError ?? "QSX is niet verbonden"));
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(url);
        reject(new Error("QSX gaf geen antwoord"));
      }, REQUEST_TIMEOUT_MS);
      this.pending.set(url, { resolve, reject, timer });
      this.socket!.write(encodeLeap(message));
    });
  }

  private failPending(err: Error): void {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(err);
    }
    this.pending.clear();
  }
}

function stationName(msg: unknown): string {
  if (!msg || typeof msg !== "object") return "";
  const body = (msg as Record<string, unknown>).Body;
  if (!body || typeof body !== "object") return "";
  const record = body as Record<string, unknown>;
  const one = record.ControlStation;
  if (one && typeof one === "object") {
    return String((one as Record<string, unknown>).Name ?? "").trim();
  }
  return "";
}

function hrefList(msg: unknown, ...keys: string[]): string[] {
  if (!msg || typeof msg !== "object") return [];
  const body = (msg as Record<string, unknown>).Body;
  if (!body || typeof body !== "object") return [];
  const record = body as Record<string, unknown>;
  const raw = keys.flatMap((key) => (Array.isArray(record[key]) ? record[key] : []));
  const hrefs: string[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const href = String((item as Record<string, unknown>).href ?? "");
    if (href.startsWith("/")) hrefs.push(href);
  }
  return hrefs;
}

function mergeZoneMessages(messages: unknown[]): unknown {
  const Zones: unknown[] = [];
  for (const msg of messages) {
    if (!msg || typeof msg !== "object") continue;
    const body = (msg as Record<string, unknown>).Body;
    if (!body || typeof body !== "object") continue;
    const zones = (body as Record<string, unknown>).Zones;
    if (Array.isArray(zones)) Zones.push(...zones);
  }
  return { Body: { Zones } };
}

function readLeapLines(socket: tls.TLSSocket, onMessage: (msg: unknown) => void): void {
  let buffer = "";
  socket.on("data", (chunk: Buffer) => {
    buffer += chunk.toString("utf8");
    let idx = buffer.indexOf("\n");
    while (idx >= 0) {
      const line = buffer.slice(0, idx).replace(/\r$/, "").trim();
      buffer = buffer.slice(idx + 1);
      idx = buffer.indexOf("\n");
      if (!line) continue;
      try {
        onMessage(JSON.parse(line));
      } catch {
        /* processor stuurt soms een lege of geen-JSON regel */
      }
    }
  });
}
