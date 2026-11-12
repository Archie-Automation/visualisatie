import tls from "node:tls";
import forge from "node-forge";
import { logger } from "../logger";
import {
  LEAP_PAIR_PORT,
  LEAP_PORT,
  type LeapSecrets,
  type LeapZone,
  buildGoToLevel,
  buildPairRequest,
  buildPingResponse,
  buildReadRequest,
  buildZoneCommand,
  encodeLeap,
  headerUrl,
  leapErrorMessage,
  parsePairingMessage,
  parseZoneList
} from "./leapMessages";

const PAIR_TIMEOUT_MS = 90_000;
const REQUEST_TIMEOUT_MS = 8_000;

export function generatePairingMaterial(): { csrPem: string; keyPem: string } {
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const csr = forge.pki.createCertificationRequest();
  csr.publicKey = keys.publicKey;
  csr.setSubject([{ name: "commonName", value: "Archie OS" }]);
  csr.sign(keys.privateKey, forge.md.sha256.create());
  return {
    csrPem: forge.pki.certificationRequestToPem(csr).replace(/\r\n/g, "\n"),
    keyPem: forge.pki.privateKeyToPem(keys.privateKey)
  };
}

/**
 * Eenmalig: TLS naar poort 8083, CSR, wachten tot iemand de knop op de
 * processor indrukt. De processor tekent dan het clientcertificaat.
 */
export function pairWithProcessor(host: string): Promise<LeapSecrets> {
  const target = host.trim();
  if (!target) return Promise.reject(new Error("Vul het IP-adres van de QSX in en sla op."));
  const { csrPem, keyPem } = generatePairingMaterial();

  return new Promise((resolve, reject) => {
    const socket = tls.connect({
      host: target,
      port: LEAP_PAIR_PORT,
      rejectUnauthorized: false,
      minVersion: "TLSv1.2"
    });
    let settled = false;
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
          "De processor reageerde niet. Houd de knop op de QSX ingedrukt tot het lampje knippert, en koppel opnieuw."
        )
      );
    }, PAIR_TIMEOUT_MS);

    socket.once("error", (err) => {
      finish(new Error(`Koppelen mislukt (${target}:${LEAP_PAIR_PORT}): ${err.message}`));
    });
    socket.once("secureConnect", () => {
      logger.info({ host: target, port: LEAP_PAIR_PORT }, "QSX-koppeling gestart");
      socket.write(encodeLeap(buildPairRequest(csrPem)));
    });
    readLeapLines(socket, (msg) => {
      const parsed = parsePairingMessage(msg);
      if (parsed.kind === "button") {
        logger.info({ host: target }, "QSX wacht op de knop op de processor");
        return;
      }
      if (parsed.kind === "error") {
        finish(new Error(parsed.message));
        return;
      }
      if (parsed.kind === "cert") {
        finish(null, {
          paired: true,
          certificate: parsed.certificate,
          privateKey: keyPem,
          rootCertificate: parsed.rootCertificate
        });
      }
    });
  });
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
  private socket?: tls.TLSSocket;
  private buffer = "";
  private pending = new Map<string, Pending>();
  private reconnectTimer?: NodeJS.Timeout;
  private stopped = false;

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

  async listZones(): Promise<LeapZone[]> {
    await this.waitConnected(REQUEST_TIMEOUT_MS);
    const zones = await this.request(buildReadRequest("/zone"), "/zone");
    const areas = await this.request(buildReadRequest("/area"), "/area");
    return parseZoneList(zones, areas);
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
    const socket = tls.connect({
      host: this.host,
      port: LEAP_PORT,
      ca: this.secrets.rootCertificate || undefined,
      cert: this.secrets.certificate,
      key: this.secrets.privateKey,
      rejectUnauthorized: Boolean(this.secrets.rootCertificate),
      minVersion: "TLSv1.2"
    });
    this.socket = socket;
    socket.setKeepAlive(true, 30_000);
    socket.once("secureConnect", () => {
      this.connected = true;
      this.lastError = undefined;
      logger.info({ host: this.host, port: LEAP_PORT }, "QSX LEAP verbonden");
    });
    socket.on("error", (err) => {
      this.lastError = err.message;
      this.connected = false;
      logger.warn({ err, host: this.host }, "QSX LEAP fout");
    });
    socket.on("close", () => {
      this.connected = false;
      this.failPending(new Error("QSX-verbinding gesloten"));
      if (this.socket === socket) this.socket = undefined;
      if (!this.stopped) {
        logger.info({ host: this.host }, "QSX LEAP gesloten — herverbinding over 10s");
        this.reconnectTimer = setTimeout(() => this.connect(), 10_000);
      }
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
