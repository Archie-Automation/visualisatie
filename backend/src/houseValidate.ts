import fs from "node:fs";
import path from "node:path";
import bcrypt from "bcryptjs";
import Ajv, { type ErrorObject } from "ajv";
import addFormats from "ajv-formats";
import type {
  HouseConfig,
  LutronButtonToKnxMapping,
  LutronHomeworksDevice,
  User
} from "./types";
import { effectiveIntercomReleaseMode } from "./intercomReleaseMode";
import { walkDevices } from "./config";

const schemaPath = path.join(__dirname, "..", "..", "config", "house.schema.json");
const raw = fs.readFileSync(schemaPath, "utf-8");
const schemaJson = JSON.parse(raw) as object;

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schemaJson);

export function stripSchemaKey(data: unknown): unknown {
  if (typeof data !== "object" || data === null) return data;
  const o = { ...(data as Record<string, unknown>) };
  delete o.$schema;
  return o;
}

export function validateHouseJson(data: unknown):
  | { ok: true; data: HouseConfig }
  | { ok: false; errors: string[] } {
  const candidate = stripSchemaKey(data);
  const ok = validate(candidate);
  if (!ok) {
    const errors = (validate.errors ?? []).map(formatAjvError);
    return { ok: false, errors };
  }
  return { ok: true, data: candidate as HouseConfig };
}

function formatAjvError(e: ErrorObject): string {
  const at = e.instancePath || "/";
  return `${at} ${e.message ?? "invalid"}`.trim();
}

/**
 * Installer may send `password` (plain text) per user; hash server-side and remove
 * the field before schema validation (schema only knows passwordHash).
 */
export async function applyPlaintextPasswords(body: unknown): Promise<void> {
  if (typeof body !== "object" || body === null) return;
  const users = (body as Record<string, unknown>).users;
  if (!Array.isArray(users)) return;
  for (const item of users) {
    if (typeof item !== "object" || item === null) continue;
    const u = item as Record<string, unknown>;
    const plain = u.password;
    if (typeof plain === "string" && plain.length > 0) {
      u.passwordHash = await bcrypt.hash(plain, 10);
      delete u.password;
    }
  }
}

/** Preserve bcrypt hashes when the installer omits or clears `passwordHash`. */
export function mergePasswordHashes(incoming: HouseConfig, previous: HouseConfig): void {
  const prevById = new Map((previous.users ?? []).map((u: User) => [u.id, u]));
  if (!incoming.users) return;
  for (const u of incoming.users) {
    if (!u.passwordHash?.trim()) {
      const old = prevById.get(u.id);
      if (old?.passwordHash) u.passwordHash = old.passwordHash;
    }
  }
}

export function assertUsersHaveHashes(cfg: HouseConfig): string | null {
  for (const u of cfg.users ?? []) {
    if (!u.passwordHash?.trim()) {
      return `Gebruiker "${u.username}" mist een passwordHash (bewaar bestaande hash of zet een bcrypt-hash).`;
    }
  }
  return null;
}

/** Extra regels na JSON-schema (o.a. openhaard stap-banden zonder overlap). */
export function validateFireplaceSemantics(cfg: HouseConfig): string[] {
  const issues: string[] = [];
  walkDevices(cfg, (d) => {
    if (d.type !== "fireplace") return;
    const flame = d.fireplace.flame;
    const sr = flame?.stepRanges;
    if (!sr || sr.length === 0) return;
    if (sr.length < 2 || sr.length > 10) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): flame.stepRanges moet 2–10 items hebben.`
      );
      return;
    }
    if (flame?.steps != null && flame.steps !== sr.length) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): flame.steps (${flame.steps}) moet gelijk zijn aan het aantal stepRanges (${sr.length}).`
      );
    }
    for (let i = 0; i < sr.length; i++) {
      const r = sr[i];
      const a = Math.round(Number(r.min));
      const b = Math.round(Number(r.max));
      if (!Number.isFinite(a) || !Number.isFinite(b)) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): stap ${i + 1} heeft ongeldige min/max.`
        );
        return;
      }
      if (a < 0 || a > 100 || b < 0 || b > 100 || a > b) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): stap ${i + 1}: min/max moeten 0–100 zijn en min ≤ max.`
        );
        return;
      }
      if (r.write !== undefined && r.write !== null) {
        const w = Math.round(Number(r.write));
        if (!Number.isFinite(w) || w < 0 || w > 100) {
          issues.push(
            `Apparaat "${d.name}" (${d.id}): stap ${i + 1}: write moet 0–100 zijn.`
          );
          return;
        }
      }
    }
    for (let i = 0; i < sr.length - 1; i++) {
      const maxI = Math.round(Number(sr[i].max));
      const minN = Math.round(Number(sr[i + 1].min));
      if (maxI >= minN) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): vlam stap ${i + 1} en ${i + 2} — ` +
            `percent-banden overlappen of raken elkaar (max van stap ${i + 1} ` +
            `moet strikt kleiner zijn dan min van stap ${i + 2}).`
        );
        return;
      }
    }
  });
  return issues;
}

export function validateRgbwWwSemantics(cfg: HouseConfig): string[] {
  const issues: string[] = [];
  walkDevices(cfg, (d) => {
    if (d.type !== "rgbw_ww") return;
    const mode = d.rgbwWw.mode;
    const ga = d.ga;
    const pb = d.rgbwWw.payloadBytes;
    if (pb !== undefined && (!Number.isFinite(pb) || pb < 1 || pb > 14)) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): rgbwWw.payloadBytes moet tussen 1 en 14 liggen.`
      );
    }
    if (mode === "channels") {
      const anyCh = ga.r || ga.g || ga.b || ga.w || ga.ww || ga.cw;
      if (!anyCh) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): rgbw_ww channels-modus vereist minstens één GA (r/g/b/w/ww/cw).`
        );
      }
    } else if (mode === "composite") {
      if (!ga.composite?.trim()) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): rgbw_ww composite-modus vereist ga.composite.`
        );
      }
    } else if (mode === "rgb232") {
      if (!ga.rgb232?.trim()) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): rgbw_ww rgb232-modus vereist ga.rgb232.`
        );
      }
    }
  });
  return issues;
}

/** Intercom: KNX-deuropen vs DoorBird — verplichte velden per modus. */
export function validateIntercomSemantics(cfg: HouseConfig): string[] {
  const issues: string[] = [];
  for (const d of cfg.intercoms ?? []) {
    if (effectiveIntercomReleaseMode(d) !== "doorbird") continue;
    const db = d.intercom.doorbird;
    if (!db?.host?.trim()) {
      issues.push(`Intercom "${d.name}" (${d.id}): DoorBird IP/hostname ontbreekt.`);
    }
    if (!db?.username?.trim()) {
      issues.push(
        `Intercom "${d.name}" (${d.id}): DoorBird-gebruikersnaam ontbreekt.`
      );
    }
    if (db?.password == null || String(db.password).length === 0) {
      issues.push(`Intercom "${d.name}" (${d.id}): DoorBird-wachtwoord ontbreekt.`);
    }
  }
  return issues;
}

const LUTRON_KNX_GA_RE = /^(\d{1,2})\/(\d{1,2})\/(\d{1,3})$/;

const LUTRON_KNX_ROLES = new Set([
  "switch",
  "dim_value",
  "byte",
  "percent",
  "temperature",
  "bit",
  "rgb232",
  "raw_bytes",
  "scene_number",
  "setpoint",
  "position"
]);

function mergeTelnetPassword(
  tel: { password?: string } | undefined,
  prevPw: string | undefined
): void {
  if (!tel) return;
  const pw = tel.password;
  if (pw != null && String(pw).trim() !== "") return;
  if (prevPw != null && String(prevPw).trim() !== "") {
    tel.password = prevPw;
  }
}

/** Telnet-wachtwoord behouden als de installateur het veld leeg laat (zoals intercom). */
export function mergeLutronTelnetPasswords(incoming: HouseConfig, previous: HouseConfig): void {
  mergeTelnetPassword(incoming.lutron?.telnet, previous.lutron?.telnet?.password);

  const prevById = new Map<string, LutronHomeworksDevice>();
  walkDevices(previous, (d) => {
    if (d.type === "lutron_homeworks") prevById.set(d.id, d);
  });
  walkDevices(incoming, (d) => {
    if (d.type !== "lutron_homeworks") return;
    const tel = d.lutronHomeworks.telnet;
    mergeTelnetPassword(tel, prevById.get(d.id)?.lutronHomeworks.telnet?.password);
  });
}

export function validateLutronSemantics(cfg: HouseConfig): string[] {
  const issues: string[] = [];

  const hl = cfg.lutron;
  if (hl) {
    const tel = hl.telnet;
    const host = (tel?.host ?? hl.bridgeHost ?? "").trim();
    if (tel?.enabled && !host) {
      issues.push(
        "Lutron: telnet staat aan maar host ontbreekt (lutron.telnet.host of lutron.bridgeHost)."
      );
    }
    const maps = hl.buttonToKnx ?? [];
    const ids = new Set<string>();
    for (const m of maps) {
      validateLutronButtonMapping(issues, "Lutron (project)", m, ids);
    }
  }

  walkDevices(cfg, (d) => {
    if (d.type !== "lutron_homeworks") return;
    const lh = d.lutronHomeworks;
    const tel = lh.telnet;
    const host = (tel?.host ?? lh.bridgeHost ?? "").trim();
    if (tel?.enabled && !host) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): Lutron telnet staat aan maar host ontbreekt (telnet.host of bridgeHost).`
      );
    }
    const maps = lh.buttonToKnx ?? [];
    const ids = new Set<string>();
    for (const m of maps) {
      validateLutronButtonMapping(issues, `Apparaat "${d.name}" (${d.id})`, m, ids);
    }
  });
  return issues;
}

function validateLutronButtonMapping(
  issues: string[],
  ctx: string,
  m: LutronButtonToKnxMapping,
  ids: Set<string>
): void {
  if (!m.id?.trim()) {
    issues.push(`${ctx}: Lutron→KNX-mapping zonder id.`);
    return;
  }
  if (ids.has(m.id)) {
    issues.push(`${ctx}: dubbele Lutron-mapping id "${m.id}".`);
  }
  ids.add(m.id);
  if (!LUTRON_KNX_GA_RE.test(m.knx.ga)) {
    issues.push(`${ctx}, mapping "${m.id}": ongeldige KNX-GA "${m.knx.ga}".`);
  }
  if (!LUTRON_KNX_ROLES.has(m.knx.role)) {
    issues.push(`${ctx}, mapping "${m.id}": KNX-rol "${m.knx.role}" is hier niet toegestaan.`);
  }
  if (m.knx.role === "raw_bytes" && !Array.isArray(m.knx.value)) {
    issues.push(`${ctx}, mapping "${m.id}": raw_bytes vereist value als byte-array.`);
  }
}

/** Lamp / zonwering met `control: "lutron"` en Lutron integration ID. */
export function validateLutronLoadOutputSemantics(cfg: HouseConfig): string[] {
  const issues: string[] = [];
  const homeworksById = new Map<string, LutronHomeworksDevice>();
  walkDevices(cfg, (d) => {
    if (d.type === "lutron_homeworks") homeworksById.set(d.id, d);
  });

  const houseHost = (cfg.lutron?.telnet?.host ?? cfg.lutron?.bridgeHost ?? "").trim();
  const houseEnabled = cfg.lutron?.telnet?.enabled === true && houseHost.length > 0;

  walkDevices(cfg, (d) => {
    if (d.type !== "light_switch" && d.type !== "light_dimmer" && d.type !== "shading") return;
    if (d.control !== "lutron") return;

    const iid =
      d.lutronIntegrationId != null
        ? Number(d.lutronIntegrationId)
        : d.lutronOutput?.integrationId != null
          ? Number(d.lutronOutput.integrationId)
          : NaN;

    if (!Number.isFinite(iid) || iid < 1) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): control=lutron vereist lutronIntegrationId (positief getal).`
      );
      return;
    }

    const legacyGw = d.lutronOutput?.homeworksDeviceId?.trim();
    if (legacyGw) {
      const hw = homeworksById.get(legacyGw);
      if (!hw) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): onbekend lutron_homeworks "${legacyGw}".`
        );
        return;
      }
      const tel = hw.lutronHomeworks.telnet;
      const host = (tel?.host ?? hw.lutronHomeworks.bridgeHost ?? "").trim();
      if (!tel?.enabled || !host) {
        issues.push(
          `Apparaat "${d.name}" (${d.id}): Lutron-gateway "${hw.name}" moet telnet.enabled en host hebben.`
        );
      }
    } else if (!houseEnabled) {
      issues.push(
        `Apparaat "${d.name}" (${d.id}): Lutron-apparaat vereist actieve koppeling onder Lutron Homeworks in technische configuratie.`
      );
    }
  });
  return issues;
}
