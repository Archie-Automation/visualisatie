/** Wie er met een intercom praat. Ringend mag elk paneel nog opnemen. */
export type IntercomLinePhase = "idle" | "ringing" | "dialing" | "busy";

const CLAIM_MS = 25_000;

type Row = { phase: IntercomLinePhase; holder?: string; at: number };

/**
 * Eén lijn per intercom.
 * `dialing` is een reservering van een paneel dat zelf belt, en vervalt
 * vanzelf als daar geen gesprek uit komt.
 */
export class IntercomLineBook {
  private rows = new Map<string, Row>();

  phase(id: string, now = Date.now()): IntercomLinePhase {
    const row = this.rows.get(id);
    if (!row) return "idle";
    if (row.phase === "dialing" && now - row.at > CLAIM_MS) {
      this.rows.delete(id);
      return "idle";
    }
    return row.phase;
  }

  /** Deurknop. Een lopend gesprek blijft bezet. */
  onRing(id: string, now = Date.now()): IntercomLinePhase {
    const cur = this.phase(id, now);
    if (cur === "busy" || cur === "dialing") return cur;
    this.rows.set(id, { phase: "ringing", at: now });
    return "ringing";
  }

  onBusy(id: string, now = Date.now()): IntercomLinePhase {
    const prev = this.rows.get(id);
    this.rows.set(id, { phase: "busy", holder: prev?.holder, at: now });
    return "busy";
  }

  onIdle(id: string): IntercomLinePhase {
    this.rows.delete(id);
    return "idle";
  }

  /** Paneel belt zelf. Alleen vanaf rust, of dezelfde houder die al belt. */
  claim(id: string, holder: string, now = Date.now()): boolean {
    const cur = this.phase(id, now);
    const row = this.rows.get(id);
    if (cur === "idle") {
      this.rows.set(id, { phase: "dialing", holder, at: now });
      return true;
    }
    if (cur === "dialing" && row?.holder === holder) {
      this.rows.set(id, { phase: "dialing", holder, at: now });
      return true;
    }
    return false;
  }

  /** Een paneel heeft deze lijn zelf geclaimd (niet een inkomende bel). */
  hasHolder(id: string, now = Date.now()): boolean {
    if (this.phase(id, now) === "idle") return false;
    return this.rows.get(id)?.holder != null;
  }

  /** Alleen de reservering, niet een gesprek dat al loopt. */
  release(id: string, holder: string, now = Date.now()): boolean {
    const row = this.rows.get(id);
    if (!row || this.phase(id, now) !== "dialing" || row.holder !== holder) {
      return false;
    }
    this.rows.delete(id);
    return true;
  }
}

export const intercomLines = new IntercomLineBook();
