/**
 * HomeWorks QSX / RadioRA 3 spreken LEAP (JSON over TLS, poort 8081).
 * Poort 8902 is de Designer-poort (binair, mutual TLS) en neemt deze
 * tekstcommando's niet aan. Koppelen gaat via LAP op poort 8083.
 */

export const LEAP_PORT = 8081;
export const LEAP_PAIR_PORT = 8083;

/** Designer- en LEAP-poorten. Daar hoort geen telnet-socket op. */
export function isLeapTransportPort(port: number | undefined): boolean {
  return port === 8902 || port === LEAP_PORT || port === LEAP_PAIR_PORT;
}

export type LeapZone = {
  id: number;
  name: string;
  controlType: string;
  area: string;
};

export type LeapSecrets = {
  paired: true;
  certificate: string;
  privateKey: string;
  rootCertificate: string;
};

export function encodeLeap(message: object): string {
  return `${JSON.stringify(message)}\r\n`;
}

export function buildPairRequest(csrPem: string): object {
  return {
    Header: {
      RequestType: "Execute",
      Url: "/pair",
      ClientTag: "archie-pair"
    },
    Body: {
      CommandType: "CSR",
      Parameters: {
        CSR: csrPem,
        DisplayName: "Archie OS",
        DeviceUID: "000000000000",
        Role: "Admin"
      }
    }
  };
}

export type PairingParse =
  | { kind: "ready" }
  | { kind: "waiting" }
  | { kind: "cert"; certificate: string; rootCertificate: string }
  | { kind: "error"; message: string }
  | { kind: "ignore" };

export function parsePairingMessage(msg: unknown): PairingParse {
  if (!msg || typeof msg !== "object") return { kind: "ignore" };
  const root = msg as Record<string, unknown>;
  const header = (root.Header ?? {}) as Record<string, unknown>;
  const body = (root.Body ?? {}) as Record<string, unknown>;
  const code = String(header.StatusCode ?? "");
  if (code.startsWith("4") || code.startsWith("5")) {
    return {
      kind: "error",
      message: String(header.Message ?? body.Message ?? `Koppelen geweigerd (${code})`)
    };
  }
  const signing = body.SigningResult as Record<string, unknown> | undefined;
  const certificate = stringField(signing?.Certificate);
  if (certificate.includes("BEGIN CERTIFICATE")) {
    const rootCertificate = stringField(signing?.RootCertificate);
    return { kind: "cert", certificate, rootCertificate };
  }
  const status = body.Status as Record<string, unknown> | undefined;
  const signingStatus = String(status?.SigningStatus ?? "");
  const permissions = Array.isArray(status?.Permissions) ? status.Permissions.map(String) : [];
  if (permissions.includes("PhysicalAccess")) return { kind: "ready" };
  if (signingStatus.toLowerCase().includes("button")) return { kind: "waiting" };
  return { kind: "ignore" };
}

/** Fouttekst van een LEAP-antwoord, of null als het commando is aanvaard. */
export function leapErrorMessage(msg: unknown): string | null {
  if (!msg || typeof msg !== "object") return null;
  const root = msg as Record<string, unknown>;
  const header = (root.Header ?? {}) as Record<string, unknown>;
  const code = String(header.StatusCode ?? "");
  const type = String(root.CommuniqueType ?? "");
  if (type === "ExceptionResponse" || code.startsWith("4") || code.startsWith("5")) {
    const body = (root.Body ?? {}) as Record<string, unknown>;
    return String(header.Message ?? body.Message ?? code ?? "QSX weigerde het commando");
  }
  return null;
}

export function headerUrl(msg: unknown): string {
  if (!msg || typeof msg !== "object") return "";
  const header = ((msg as Record<string, unknown>).Header ?? {}) as Record<string, unknown>;
  return String(header.Url ?? "");
}

/**
 * De processor stuurt zelf een ping. Zonder ReadResponse verbreekt QSX de
 * sessie. Andere berichten geven null.
 */
export function buildPingResponse(msg: unknown): object | null {
  if (!msg || typeof msg !== "object") return null;
  const root = msg as Record<string, unknown>;
  if (root.CommuniqueType !== "ReadRequest") return null;
  const url = headerUrl(msg);
  if (!url.includes("/status/ping")) return null;
  const header = (root.Header ?? {}) as Record<string, unknown>;
  const tag = header.ClientTag;
  return {
    CommuniqueType: "ReadResponse",
    Header: {
      StatusCode: "200 OK",
      Url: url,
      ...(tag != null && tag !== "" ? { ClientTag: tag } : {})
    }
  };
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value : "";
}

export function formatFade(seconds: number): string {
  const total = Math.max(0, Math.min(14_400, Math.round(seconds)));
  const hh = Math.floor(total / 3600);
  const mm = Math.floor((total % 3600) / 60);
  const ss = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(hh)}:${pad(mm)}:${pad(ss)}`;
}

export function buildReadRequest(url: string): object {
  return { CommuniqueType: "ReadRequest", Header: { Url: url } };
}

export function buildSubscribeRequest(url: string): object {
  return { CommuniqueType: "SubscribeRequest", Header: { Url: url } };
}

export type LeapButton = {
  id: number;
  name: string;
  buttonNumber: number;
  /** Keypad of control station waar de knop op zit. */
  deviceName: string;
};

export type LeapButtonPress = {
  id: number;
  /** Zelfde nummers als de installateur: 3 druk, 4 los, 5 lang, 6 dubbel. */
  action: number;
};

/** Press/Release/LongHold/MultiTap → de actienummers van de keypad-mapping. */
export function leapButtonAction(eventType: string): number | null {
  switch (eventType) {
    case "Press":
      return 3;
    case "Release":
      return 4;
    case "LongHold":
    case "Hold":
      return 5;
    case "MultiTap":
      return 6;
    default:
      return null;
  }
}

export function parseButtonList(msg: unknown, deviceName = ""): LeapButton[] {
  return collectDefinedButtons(msg, deviceName);
}

/**
 * QSX wijst `/button` vaak af. Knoppen zitten dan op een control station
 * of in een buttongroep van het keypad. Een kaal `{href}` is nog geen knop.
 */
export function collectDefinedButtons(msg: unknown, deviceName = ""): LeapButton[] {
  const byId = new Map<number, LeapButton>();
  const visit = (node: unknown, device: string) => {
    if (Array.isArray(node)) {
      for (const item of node) visit(item, device);
      return;
    }
    if (!node || typeof node !== "object") return;
    const rec = node as Record<string, unknown>;
    let nextDevice = device;
    const href = String(rec.href ?? "");
    if (hrefId(href, "device") != null || hrefId(href, "controlstation") != null) {
      const named = String(rec.Name ?? "").trim();
      if (named) nextDevice = named;
    }
    const id = hrefId(href, "button");
    if (id != null && buttonIsDefined(rec) && !byId.has(id)) {
      const number = Number(rec.ButtonNumber);
      byId.set(id, {
        id,
        name: buttonLabel(rec, id),
        buttonNumber: Number.isFinite(number) ? number : 0,
        deviceName: ownerName(rec, nextDevice)
      });
    }
    for (const value of Object.values(rec)) visit(value, nextDevice);
  };
  visit(msg, deviceName);
  return [...byId.values()].sort((a, b) => a.id - b.id);
}

export function collectHrefs(msg: unknown, kind: string): string[] {
  const found = new Set<string>();
  const visit = (node: unknown) => {
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    if (!node || typeof node !== "object") return;
    const rec = node as Record<string, unknown>;
    const href = String(rec.href ?? "");
    const id = hrefId(href, kind);
    if (id != null) found.add(`/${kind}/${id}`);
    for (const value of Object.values(rec)) visit(value);
  };
  visit(msg);
  return [...found];
}

export type LeapDeviceRef = { href: string; name: string; deviceType: string };

export function collectDevices(msg: unknown): LeapDeviceRef[] {
  const byHref = new Map<string, LeapDeviceRef>();
  const visit = (node: unknown) => {
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    if (!node || typeof node !== "object") return;
    const rec = node as Record<string, unknown>;
    const href = String(rec.href ?? "");
    const id = hrefId(href, "device");
    if (id != null) {
      const key = `/device/${id}`;
      const prev = byHref.get(key);
      const name = String(rec.Name ?? "").trim();
      const deviceType = String(rec.DeviceType ?? rec.FullyQualifiedType ?? "").trim();
      byHref.set(key, {
        href: key,
        name: name || prev?.name || "",
        deviceType: deviceType || prev?.deviceType || ""
      });
    }
    for (const value of Object.values(rec)) visit(value);
  };
  visit(msg);
  return [...byHref.values()];
}

/** Loads zonder knoppen overslaan. Een schakelaar of dimmer heeft vaak wél knoppen. */
export function deviceMayHaveButtons(deviceType: string): boolean {
  const type = deviceType.toLowerCase();
  if (!type) return true;
  if (/keypad|pico|seetouch|sunnata|palladiom|grafik|tabletop|hybrid|remote|switch|dimmer/.test(type)) {
    return true;
  }
  return !/shade|processor|repeater|interface|contact|module|panel|sensor|occupancy|thermostat|fan|receptacle|phase|drape|blind|motor|output|lamp/.test(
    type
  );
}

/** `/button/614` uit het integratierapport, ook als de processor alleen het href stuurt. */
export function buttonStubFromHref(href: string, deviceName = ""): LeapButton | null {
  const id = hrefId(href, "button");
  if (id == null) return null;
  return { id, name: `Knop ${id}`, buttonNumber: 0, deviceName };
}

function ownerName(rec: Record<string, unknown>, fallback: string): string {
  const parent = rec.Parent ?? rec.Device;
  if (parent && typeof parent === "object") {
    const named = String((parent as Record<string, unknown>).Name ?? "").trim();
    if (named) return named;
  }
  return fallback;
}

function buttonIsDefined(rec: Record<string, unknown>): boolean {
  if (rec.ButtonNumber != null || rec.Engraving != null || rec.ProgrammingModel != null) {
    return true;
  }
  return typeof rec.Name === "string" && rec.Name.trim() !== "";
}

function buttonLabel(rec: Record<string, unknown>, id: number): string {
  const engraving = rec.Engraving;
  if (engraving && typeof engraving === "object") {
    const text = String((engraving as Record<string, unknown>).Text ?? "").trim();
    if (text) return text;
  }
  const name = String(rec.Name ?? "").trim();
  return name || `Knop ${id}`;
}

function hrefId(href: string, kind: string): number | null {
  const parts = href.split("/").filter(Boolean);
  if (parts.length !== 2 || parts[0] !== kind) return null;
  const id = Number(parts[1]);
  return Number.isFinite(id) && id >= 1 ? id : null;
}

export function parseButtonEvents(msg: unknown): LeapButtonPress[] {
  const body = bodyOf(msg);
  const single = body.ButtonStatus;
  const many = arrayOf(body.ButtonStatuses);
  const statuses =
    single && typeof single === "object" ? [single as Record<string, unknown>, ...many] : many;
  const out: LeapButtonPress[] = [];
  for (const status of statuses) {
    const event = status.ButtonEvent;
    if (!event || typeof event !== "object") continue;
    const action = leapButtonAction(String((event as Record<string, unknown>).EventType ?? ""));
    if (action == null) continue;
    const button = status.Button as Record<string, unknown> | undefined;
    const id = buttonIdFromHref(String(button?.href ?? headerUrl(msg)));
    if (id == null) continue;
    out.push({ id, action });
  }
  return out;
}

function buttonIdFromHref(href: string): number | null {
  const parts = href.split("/").filter(Boolean);
  const at = parts.indexOf("button");
  const raw = at >= 0 ? parts[at + 1] : parts[parts.length - 1];
  const id = Number(raw);
  return Number.isFinite(id) && id >= 1 ? id : null;
}

export function buildGoToLevel(zoneId: number, percent: number, fadeSeconds?: number): object {
  const level = Math.max(0, Math.min(100, Math.round(percent)));
  const parameter: { Type: string; Value: number | string }[] = [
    { Type: "Level", Value: level }
  ];
  if (fadeSeconds != null && fadeSeconds > 0) {
    parameter.push({ Type: "FadeTime", Value: formatFade(fadeSeconds) });
  }
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: {
      Command: {
        CommandType: "GoToLevel",
        Parameter: parameter
      }
    }
  };
}

export function buildZoneCommand(
  zoneId: number,
  commandType: "Raise" | "Lower" | "Stop"
): object {
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: { Command: { CommandType: commandType } }
  };
}

/** Lamellen op dezelfde QSX-zone. Een tweede zone-id is alleen nodig als Designer ze splitst. */
export function buildGoToTilt(zoneId: number, percent: number): object {
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: {
      Command: {
        CommandType: "GoToTilt",
        TiltParameters: { Tilt: clampPercent(percent) }
      }
    }
  };
}

/**
 * Clear Connect Type X kleur (Ketra / Lumaris / SpectrumTune) op de QSX.
 * Hue 0–360, saturation en level 0–100.
 */
export function buildSpectrum(
  zoneId: number,
  level: number,
  hue: number,
  saturation: number
): object {
  const hueDeg = ((Math.round(hue) % 360) + 360) % 360;
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: {
      Command: {
        CommandType: "GoToSpectrumTuningLevel",
        SpectrumTuningLevelParameters: {
          Level: clampPercent(level),
          ColorTuningStatus: {
            HSVTuningLevel: {
              Hue: hueDeg,
              Saturation: clampPercent(saturation)
            }
          }
        }
      }
    }
  };
}

/** Tunable white op een zone die alleen wit kan. Kelvin typisch 2700–6500. */
export function buildWhite(zoneId: number, level: number, kelvin: number): object {
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: {
      Command: {
        CommandType: "GoToWhiteTuningLevel",
        WhiteTuningLevelParameters: {
          Level: clampPercent(level),
          WhiteTuningLevel: { Kelvin: kelvinOf(kelvin) }
        }
      }
    }
  };
}

/**
 * Kleurtemperatuur op een SpectrumTune-zone. GoToWhiteTuningLevel laat die
 * zone in de laatste HSV-kleur staan.
 */
export function buildSpectrumWhite(zoneId: number, level: number, kelvin: number): object {
  return {
    CommuniqueType: "CreateRequest",
    Header: { Url: `/zone/${zoneId}/commandprocessor` },
    Body: {
      Command: {
        CommandType: "GoToSpectrumTuningLevel",
        SpectrumTuningLevelParameters: {
          Level: clampPercent(level),
          ColorTuningStatus: {
            WhiteTuningLevel: { Kelvin: kelvinOf(kelvin) }
          }
        }
      }
    }
  };
}

function kelvinOf(kelvin: number): number {
  return Math.max(1000, Math.min(25000, Math.round(kelvin)));
}

function clampPercent(n: number): number {
  return Math.max(0, Math.min(100, Math.round(n)));
}

export type LeapZoneLive = {
  id: number;
  /** Huidige stand 0–100. 0 is uit. */
  level: number;
  /** Laatste stand boven 0. Aan zetten gaat hierheen, niet naar 100. */
  recall: number;
  hue?: number;
  saturation?: number;
  kelvin?: number;
};

/** Aan = laatste dimstand. Een schakelaar (geen dimmer) gaat wel naar 100. */
export function switchLevelFromRecall(
  recall: number | undefined,
  on: boolean,
  fullOn: boolean
): number {
  if (!on) return 0;
  if (fullOn) return 100;
  if (recall != null && recall > 0) {
    return Math.max(1, Math.min(100, Math.round(recall)));
  }
  return 100;
}

export function parseZoneLevels(msg: unknown): LeapZoneLive[] {
  const body = bodyOf(msg);
  const single = body.ZoneStatus;
  const many = arrayOf(body.ZoneStatuses);
  const rows =
    single && typeof single === "object"
      ? [single as Record<string, unknown>, ...many]
      : many;
  const out: LeapZoneLive[] = [];
  for (const row of rows) {
    const id = zoneIdOf(row);
    if (id == null) continue;
    const level = zoneLevelOf(row);
    if (level == null) continue;
    const color = row.ColorTuningStatus;
    const hsv =
      color && typeof color === "object"
        ? ((color as Record<string, unknown>).HSVTuningLevel as Record<string, unknown> | undefined)
        : undefined;
    const white =
      color && typeof color === "object"
        ? ((color as Record<string, unknown>).WhiteTuningLevel as Record<string, unknown> | undefined)
        : undefined;
    const hue = numberOrUndefined(hsv?.Hue);
    const saturation = numberOrUndefined(hsv?.Saturation);
    const kelvin = numberOrUndefined(white?.Kelvin);
    out.push({
      id,
      level,
      recall: level > 0 ? level : 0,
      ...(hue != null ? { hue } : {}),
      ...(saturation != null ? { saturation } : {}),
      ...(kelvin != null ? { kelvin } : {})
    });
  }
  return out;
}

function zoneIdOf(row: Record<string, unknown>): number | null {
  const zone = row.Zone;
  const href = String(
    (zone && typeof zone === "object" ? (zone as Record<string, unknown>).href : undefined) ??
      row.href ??
      ""
  );
  const parts = href.split("/").filter(Boolean);
  const at = parts.indexOf("zone");
  const raw = at >= 0 ? parts[at + 1] : "";
  if (!raw || raw === "status") return null;
  const id = Number(raw);
  return Number.isFinite(id) && id >= 1 ? id : null;
}

function zoneLevelOf(row: Record<string, unknown>): number | null {
  const level = numberOrUndefined(row.Level);
  if (level != null) return Math.max(0, Math.min(100, Math.round(level)));
  const switched = String(row.SwitchedLevel ?? "");
  if (switched === "On") return 100;
  if (switched === "Off") return 0;
  return null;
}

function numberOrUndefined(value: unknown): number | undefined {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : undefined;
}

export function parseZoneList(zoneMsg: unknown, areaMsg: unknown): LeapZone[] {
  const areas = new Map<string, string>();
  const areaBody = bodyOf(areaMsg);
  const areaList = arrayOf(areaBody.Areas ?? areaBody.AreaSummaries);
  for (const area of areaList) {
    const href = String(area.href ?? "");
    const name = String(area.Name ?? "").trim();
    if (href && name) areas.set(href, name);
  }

  const zoneBody = bodyOf(zoneMsg);
  const raw = arrayOf(zoneBody.Zones);
  const expanded = arrayOf(zoneBody.ZoneExpandedStatuses).map((row) => {
    const zone = row.Zone;
    return zone && typeof zone === "object" ? (zone as Record<string, unknown>) : row;
  });
  const zones = raw.length > 0 ? raw : expanded;
  const out: LeapZone[] = [];
  for (const zone of zones) {
    const href = String(zone.href ?? "");
    const id = Number(href.split("/").filter(Boolean).pop());
    if (!Number.isFinite(id) || id < 1) continue;
    const areaHref = String(
      (zone.AssociatedArea as Record<string, unknown> | undefined)?.href ?? ""
    );
    out.push({
      id,
      name: String(zone.Name ?? `Zone ${id}`),
      controlType: String(zone.ControlType ?? ""),
      area: areas.get(areaHref) ?? ""
    });
  }
  out.sort((a, b) => a.id - b.id);
  return out;
}

function bodyOf(msg: unknown): Record<string, unknown> {
  if (!msg || typeof msg !== "object") return {};
  const body = (msg as Record<string, unknown>).Body;
  return body && typeof body === "object" ? (body as Record<string, unknown>) : {};
}

function arrayOf(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item) => item && typeof item === "object") as Record<string, unknown>[];
}
