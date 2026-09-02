import net from "node:net";
import { logger } from "../logger";

export type AmiFields = Record<string, string>;

type Pending = {
  resolve: (events: AmiFields[]) => void;
  reject: (err: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  events: AmiFields[];
};

/**
 * Minimal Asterisk Manager Interface client (TCP).
 * No extra npm dependency — AMI is a line protocol.
 */
export class AmiClient {
  private sock: net.Socket | null = null;
  private buf = "";
  private actionId = 0;
  private pending = new Map<string, Pending>();
  private greeting = false;
  private onEvent: ((ev: AmiFields) => void) | null = null;

  constructor(
    private readonly host: string,
    private readonly port: number
  ) {}

  setEventHandler(fn: (ev: AmiFields) => void): void {
    this.onEvent = fn;
  }

  get connected(): boolean {
    return this.sock != null && !this.sock.destroyed;
  }

  connect(username: string, secret: string): Promise<void> {
    this.close();
    return new Promise((resolve, reject) => {
      const sock = net.connect({ host: this.host, port: this.port });
      this.sock = sock;
      let settled = false;
      const fail = (err: Error) => {
        if (settled) return;
        settled = true;
        reject(err);
      };
      sock.setEncoding("utf8");
      sock.on("error", (err) => {
        logger.warn({ err }, "AMI socket error");
        fail(err);
      });
      sock.on("close", () => {
        this.sock = null;
        this.greeting = false;
        for (const p of this.pending.values()) {
          clearTimeout(p.timer);
          p.reject(new Error("AMI disconnected"));
        }
        this.pending.clear();
      });
      sock.on("data", (chunk: string) => {
        this.buf += chunk;
        this.drain();
        if (!this.greeting && this.sawGreeting) {
          this.greeting = true;
          this.send({ Action: "Login", Username: username, Secret: secret })
            .then((evs) => {
              const r = evs[0];
              if (r?.Response === "Success") {
                settled = true;
                resolve();
              } else {
                fail(new Error(r?.Message || "AMI login failed"));
              }
            })
            .catch(fail);
        }
      });
    });
  }

  private sawGreeting = false;

  private drain(): void {
    while (true) {
      const idx = this.buf.indexOf("\r\n\r\n");
      if (idx < 0) return;
      const raw = this.buf.slice(0, idx);
      this.buf = this.buf.slice(idx + 4);
      if (raw.startsWith("Asterisk Call Manager")) {
        this.sawGreeting = true;
        continue;
      }
      const fields = parseAmiBlock(raw);
      const aid = fields.ActionID;
      if (aid && this.pending.has(aid)) {
        const p = this.pending.get(aid)!;
        p.events.push(fields);
        if (fields.EventList === "Complete" || fields.Response === "Error" ||
          (fields.Response && fields.EventList !== "start")) {
          if (fields.EventList === "start") continue;
          if (fields.Response === "Success" && fields.EventList === "start") continue;
        }
        const complete =
          fields.EventList === "Complete" ||
          fields.Response === "Error" ||
          (fields.Response === "Success" && !fields.EventList);
        if (complete) {
          clearTimeout(p.timer);
          this.pending.delete(aid);
          p.resolve(p.events);
        }
      } else if (fields.Event) {
        this.onEvent?.(fields);
      }
    }
  }

  send(fields: AmiFields, timeoutMs = 8000): Promise<AmiFields[]> {
    const sock = this.sock;
    if (!sock) return Promise.reject(new Error("AMI not connected"));
    const id = String(++this.actionId);
    const body = { ...fields, ActionID: id };
    const payload =
      Object.entries(body)
        .map(([k, v]) => `${k}: ${v}`)
        .join("\r\n") + "\r\n\r\n";
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("AMI timeout"));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer, events: [] });
      sock.write(payload);
    });
  }

  async command(cmd: string): Promise<void> {
    await this.send({ Action: "Command", Command: cmd });
  }

  close(): void {
    try {
      this.sock?.destroy();
    } catch {
      /* ignore */
    }
    this.sock = null;
  }
}

function parseAmiBlock(raw: string): AmiFields {
  const out: AmiFields = {};
  for (const line of raw.split(/\r?\n/)) {
    const c = line.indexOf(": ");
    if (c < 0) continue;
    const k = line.slice(0, c);
    const v = line.slice(c + 2);
    out[k] = v;
  }
  return out;
}
