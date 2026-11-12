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
      CommandType: "Execute",
      Parameters: {
        CSR: csrPem,
        DisplayName: "Archie OS",
        DeviceUID: "archie-os"
      }
    }
  };
}

export type PairingParse =
  | { kind: "button" }
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
  if (
    signingStatus.toLowerCase().includes("button") ||
    permissions.includes("PhysicalAccess")
  ) {
    return { kind: "button" };
  }
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
