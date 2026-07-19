import fs from "node:fs";
import path from "node:path";
import { XMLParser } from "fast-xml-parser";

/**
 * KNX Group Address XML import.
 *
 * Reads a KNX "GroupAddress-Export" XML (the format exported by ETS 5/6 and by
 * the Archie Groepsadressentool). Produces:
 *   1. A flat, searchable GA catalog (address + name + DPT) for manual device
 *      wiring in the installer UI.
 *   2. A proposal of "hoofdfunctie" devices (light on/off, dimmers, RGBW,
 *      shading, climate) grouped per floor/room, reconstructed from the
 *      structured GA names + DPTs.
 *
 * Naming convention understood (Archie tool default):
 *   {verdieping.ruimte} {ruimtenaam} {devicenaam} {schakelcode} {objectnaam}
 *   e.g. "0.3 woonkamer spots bank aan/uit"
 * -> dimbare lamp "spots bank", begane grond, woonkamer.
 */

const configPath = path.resolve(
  process.env.CONFIG_PATH ?? path.join(__dirname, "..", "..", "config", "house.json")
);
const catalogPath = path.resolve(
  process.env.KNX_GA_CATALOG_PATH ??
    path.join(path.dirname(configPath), "knx-ga-catalog.json")
);

export interface GaCatalogEntry {
  /** "m/mi/s" three-level group address. */
  address: string;
  /** Full group address name as it appears in the export. */
  name: string;
  /** Datapoint type, normalized to "DPT<main>.<sub>" (may be empty). */
  dpt: string;
  /** Main group name (context), when available. */
  mainGroup?: string;
  /** Middle group name (context), when available. */
  middleGroup?: string;
}

/** A device as a plain house.json map (id/type/name/ga/...). */
export type ProposedDevice = Record<string, unknown>;

export interface ProposedRoom {
  /** "F.R" unique room code (e.g. "0.3"). */
  code: string;
  floor: number;
  room: number;
  name: string;
  devices: ProposedDevice[];
}

export interface ProposedFloor {
  floor: number;
  name: string;
  rooms: ProposedRoom[];
}

export interface ReviewItem {
  address?: string;
  name: string;
  reason: string;
}

/** Categorized "please check this" list for the installer/programmer. */
export interface KnxImportReview {
  /** Recognized but NOT auto-created (sockets, fireplace, fountain, mirror
   *  heating, AC, ...). They live in the catalog; add manually if wanted. */
  manualDevices: ReviewItem[];
  /** Devices auto-renamed because a room had duplicate names. */
  duplicateNames: ReviewItem[];
  /** Rooms whose name was guessed from a single device. */
  singleDeviceRooms: ReviewItem[];
  /** GAs inside a device section whose role wasn't recognized. */
  unclassified: ReviewItem[];
  /** Reconstructed RGB(W) devices — verify the channel grouping. */
  rgbwGroups: ReviewItem[];
  /** Devices whose actuator Description spans a channel range (e.g. "A1-2"),
   *  i.e. one GA switches several contacts/lamps together — verify intent. */
  groupChannelDevices: ReviewItem[];
  /** Imported airco devices — the installer must verify mode/fan values map
   *  onto the unit's ETS enum (DPT 20.105 / 5.001) before use. */
  acDevices: ReviewItem[];
}

export interface KnxImportResult {
  catalog: GaCatalogEntry[];
  floors: ProposedFloor[];
  skipped: Array<{ address: string; name: string; reason: string }>;
  warnings: string[];
  review: KnxImportReview;
  stats: {
    addresses: number;
    devices: number;
    floors: number;
    rooms: number;
    manual: number;
    unclassified: number;
    groupChannel: number;
    ac: number;
  };
}

/* ------------------------------------------------------------------ */
/*  Address + DPT helpers                                             */
/* ------------------------------------------------------------------ */

/** ETS exports store the leaf Address as a linear 16-bit int; the Archie tool
 *  stores it as "m/mi/s". Normalize both to a three-level string. */
export function normalizeAddress(raw: string): string {
  const s = String(raw).trim();
  if (s.includes("/")) return s;
  const n = Number(s);
  if (!Number.isFinite(n)) return s;
  const main = (n >> 11) & 0x1f;
  const middle = (n >> 8) & 0x7;
  const sub = n & 0xff;
  return `${main}/${middle}/${sub}`;
}

/** "DPST-1-1" or "DPT1.001" -> { main, sub }. First entry of a comma list. */
function parseDpt(dpts: string | undefined): { main: number; sub: number } | null {
  if (!dpts) return null;
  const first = String(dpts).split(",")[0]?.trim();
  if (!first) return null;
  let m = first.match(/^DPST-(\d+)-(\d+)$/i);
  if (m) return { main: parseInt(m[1]!, 10), sub: parseInt(m[2]!, 10) };
  m = first.match(/^DPS?T-?(\d+)[.\-](\d+)$/i);
  if (m) return { main: parseInt(m[1]!, 10), sub: parseInt(m[2]!, 10) };
  return null;
}

/** Normalize a DPT string to "DPT<main>.<sub>" for the catalog. */
function normalizeDpt(dpts: string | undefined): string {
  const p = parseDpt(dpts);
  if (!p) return "";
  return `DPT${p.main}.${String(p.sub).padStart(3, "0")}`;
}

/* ------------------------------------------------------------------ */
/*  XML traversal                                                     */
/* ------------------------------------------------------------------ */

interface RawLeaf {
  address: string;
  name: string;
  dpts: string;
  mainGroup: string;
  middleGroup: string;
  /** ETS "Description": the physical actuator channel (e.g. "1.1.14 uitgang A1").
   *  All GAs of one physical output share it, so it is the most reliable key to
   *  merge on/off + dim + value + status of ONE device — and to keep two
   *  identically-named outputs apart. */
  description: string;
}

function asArray(v: unknown): Record<string, unknown>[] {
  if (v === undefined || v === null) return [];
  const arr = Array.isArray(v) ? v : [v];
  return arr.filter(
    (x): x is Record<string, unknown> => typeof x === "object" && x !== null
  );
}

/** Collect every GroupAddress leaf with its main/middle group context. */
function collectLeaves(xml: string): RawLeaf[] {
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    parseAttributeValue: false,
    trimValues: true,
  });
  const doc = parser.parse(xml) as Record<string, unknown>;
  const root =
    (doc["GroupAddress-Export"] as Record<string, unknown> | undefined) ??
    (doc["GroupAddressExport"] as Record<string, unknown> | undefined);
  if (!root) return [];

  const leaves: RawLeaf[] = [];

  const pushLeaf = (ga: Record<string, unknown>, main: string, middle: string) => {
    const addr = ga["@_Address"];
    if (addr === undefined || addr === null) return;
    leaves.push({
      address: normalizeAddress(String(addr)),
      name: String(ga["@_Name"] ?? "").trim(),
      dpts: String(ga["@_DPTs"] ?? ga["@_DatapointType"] ?? "").trim(),
      mainGroup: main,
      middleGroup: middle,
      description: String(ga["@_Description"] ?? "").trim(),
    });
  };

  // GroupRange can be nested 1-2 levels deep (main -> middle -> address) or
  // flat (main -> address). Walk recursively, tracking the two outermost
  // range names as main/middle context.
  const walkRange = (
    range: Record<string, unknown>,
    depth: number,
    mainName: string,
    middleName: string
  ) => {
    const name = String(range["@_Name"] ?? "").trim();
    const nextMain = depth === 0 ? name : mainName;
    const nextMiddle = depth === 1 ? name : middleName;
    for (const ga of asArray(range["GroupAddress"])) {
      pushLeaf(ga, nextMain, nextMiddle);
    }
    for (const child of asArray(range["GroupRange"])) {
      walkRange(child, depth + 1, nextMain, nextMiddle);
    }
  };

  for (const range of asArray(root["GroupRange"])) {
    walkRange(range, 0, "", "");
  }
  // Some exports place GroupAddress leaves directly at the root.
  for (const ga of asArray(root["GroupAddress"])) {
    pushLeaf(ga, "", "");
  }

  return leaves;
}

/* ------------------------------------------------------------------ */
/*  Name parsing + role classification                               */
/* ------------------------------------------------------------------ */

/** "{verdieping}.{ruimte}{optionele letter}" prefix. The trailing letter (k/p/…)
 *  denotes a DISTINCT room that shares the same number (e.g. 0.01 woonkamer vs
 *  0.01k kantoor), so it is part of the room identity — not a throwaway. */
const FLOOR_ROOM_RE = /^(-?\d+)\.(\d+)([a-zA-Z]?)/;

/** Tokens that indicate a status/feedback object rather than a command. */
const STATUS_RE =
  /(status|\bstate\b|terugmeld|statusmeld|feedback|\bfb\b|r[uü]ckmeld|meldung)/i;

/** Known trailing object-name tokens (single token forms), for stripping. */
const OBJECT_TOKEN_RE =
  /^(aan\/uit|aan|uit|schakelen|schakeling|dimmen|dim|dimwaarde|dimwaarden|waarde|helderheid|absoluut|status|terugmelding|melding|feedback|op\/neer|op|neer|omhoog|omlaag|omhoog\/omlaag|jaloezie|jalouzie|rolluik|zonwering|screen|stop|step|stap|stop\/step|positie|positiewaarde|hoogte|pos|lamel|lamellen|lamelstand|slat|kanteling|setpoint|gewenst|gewenste|streeftemperatuur|soll|gemeten|actueel|actuele|temperatuur|ist|rood|groen|blauw|wit|warmwit|koudwit|kleur|r|g|b|w|ww|cw|on\/off|on|off|switch|value|brightness|dimming|position|height|up|down|tilt|red|green|blue|white|warmwhite|coolwhite|colour|color|desired|target|temperature|mode|measured|actual|current|state|ein|aus|ein\/aus|schalten|wert|helligkeit|h[oö]he|hoch|runter|stopp|schritt|lamelle|wende|rot|gr[uü]n|blau|wei[sß]|warmwei[sß]|kaltwei[sß]|modus|wunsch|raumtemperatur)$/i;

/** A switch/output code. Two real-world shapes:
 *   - digit-first (Archie lighting):  1b, 4ab, 1e2, 6am1, 8bu4, 2s1, 3aa
 *   - letter-first (shading / ETS):   zw1, zw9, L1, U3, da1.1
 *  A pure word ("voor", "haard", "wastafel") never matches (needs a digit). */
const SWITCH_CODE_RE =
  /^(\d{1,2}[a-z]{1,3}\d{0,2}|[a-z]{1,3}\d{1,3}(?:[.\-]\d{1,3})?)$/i;

/** GroupRange sections that hold central-switching, scenes, faults, triggers,
 *  AC and other non-"hoofdfunctie" addresses. Their leaves stay in the
 *  searchable catalog but never auto-generate a device. */
function isNonDeviceSection(mainGroup: string, middleGroup: string): boolean {
  const s = `${mainGroup} ${middleGroup}`.toLowerCase();
  if (
    /(centraal|central|zentral|scene|szene|blokker|trigger|alarm|storing|st[oö]rung|fault|kortsluit|overbelast|overload|belastingstype|\becg\b|fout)/.test(
      s
    )
  )
    return true;
  if (/\bac\b/.test(s)) return true; // airco: add manually
  // umbrella group for centraal/scenes (NL "algemeen" | EN "general" | DE "allgemein")
  if (/\balgemeen\b|\bgeneral\b|\ballgemein\b/.test(s)) return true;
  return false;
}

/** True for the dedicated per-room climate section (mainGroup "Klimaat"). */
function isClimateSection(mainGroup: string): boolean {
  return /klimaat|klima\b|climate|hvac|thermostaat|thermostat/i.test(mainGroup);
}

/** Placeholder / empty GA names that add only noise to the catalog. */
function isNoiseName(name: string): boolean {
  const t = name.trim().toLowerCase();
  return t === "" || /^-+$/.test(t) || t === "reserve" || t === "reserved";
}

type RoleCategory = "switch" | "dim" | "shade" | "climate" | "rgb";

interface Classified {
  gaKey: string;
  cat: RoleCategory;
}

function matchRgbChannel(t: string): string | null {
  if (/(warmwit|warm wit|warmwhite|warm white|warmwei[sß]|\bww\b)/i.test(t))
    return "ww";
  if (/(koudwit|koud wit|coolwhite|cool white|kaltwei[sß]|\bcw\b)/i.test(t))
    return "cw";
  if (/(\brood\b|\bred\b|\brot\b|\br\b)/i.test(t)) return "r";
  if (/(\bgroen\b|\bgreen\b|\bgr[uü]n\b|\bg\b)/i.test(t)) return "g";
  if (/(\bblauw?\b|\bblue\b|\bb\b)/i.test(t)) return "b";
  if (/(\bwit\b|\bwhite\b|\bwei[sß]s?\b|\bw\b)/i.test(t)) return "w";
  return null;
}

/** Determine the house.json ga role for an object, from its text + DPT. */
function classify(objectText: string, dpt: { main: number; sub: number } | null): Classified | null {
  const t = objectText.toLowerCase();
  const isStatus = STATUS_RE.test(t);

  // Shading (check position/slat text before the generic DPT5 dim branch).
  // Keywords: NL | EN | DE.
  if (dpt?.main === 1 && dpt.sub === 8) return { gaKey: "up_down", cat: "shade" };
  if (
    /(op\/neer|op neer|omhoog|omlaag|jalouz|jaloez|rolluik|up\/down|up down|auf\/ab|auf ab|hoch|runter|rolll?aden)/.test(
      t
    )
  )
    return { gaKey: "up_down", cat: "shade" };
  if (/(stop|step|stap|stopp|schritt)/.test(t)) return { gaKey: "stop_step", cat: "shade" };
  if (/(lamel|slat|kantel|tilt|lamelle|wende)/.test(t))
    return { gaKey: isStatus ? "slat_status" : "slat", cat: "shade" };
  if (/(\bpositie|\bposition|\bhoogte\b|\bh[oö]he\b|\bheight\b|\bpos\b)/.test(t))
    return { gaKey: isStatus ? "position_status" : "position", cat: "shade" };

  // Climate
  if (/(gemeten|actue|\bist\b|isttemp|istwert|ruimtetemp|measured|actual|current|raumtemp)/.test(t))
    return { gaKey: "actual_temp", cat: "climate" };
  if (/(setpoint|gewenst|streef|soll|desired|target|wunsch)/.test(t))
    return { gaKey: isStatus ? "setpoint_status" : "setpoint", cat: "climate" };
  if (dpt?.main === 9) {
    if (/temperat/.test(t)) return { gaKey: "actual_temp", cat: "climate" };
    return { gaKey: isStatus ? "setpoint_status" : "setpoint", cat: "climate" };
  }

  // RGB(W) channels
  const rgb = matchRgbChannel(t);
  if (rgb) return { gaKey: rgb, cat: "rgb" };

  // Relative dimming (DPT 3.007, 4-bit up/down). Signals the device is a
  // dimmer, but the app steers brightness via the absolute value GA — so we
  // mark the category without occupying a stored ga slot.
  if (
    dpt?.main === 3 ||
    (/\bdimm(en|ing)?\b/.test(t) &&
      !/(waarde|value|wert|brightness|helligkeit)/.test(t))
  )
    return { gaKey: "", cat: "dim" };

  // Absolute dim value (DPT 5.001 "waarde"/"helderheid"/"brightness").
  if (
    dpt?.main === 5 ||
    /(dimwaarde|helderheid|waarde|brightness|helligkeit|\bvalue\b|\bwert\b|\bdim\b)/.test(
      t
    )
  )
    return { gaKey: isStatus ? "dim_status" : "dim_value", cat: "dim" };

  // Switching
  if (
    dpt?.main === 1 ||
    /(aan|uit|schakel|schalt|licht|light|on\/off|on off|\bein\b|\baus\b|switch)/.test(
      t
    )
  )
    return { gaKey: isStatus ? "switch_status" : "switch", cat: "switch" };

  return null;
}

interface ParsedLeaf extends RawLeaf {
  floor: number;
  room: number;
  /** Unique room identity incl. any letter suffix, e.g. "0.01" / "0.01k". */
  roomCode: string;
  /** Core tokens after the floor.room prefix, with trailing object tokens removed. */
  coreTokens: string[];
  /** Core tokens without a trailing switch code. */
  coreNoCode: string[];
  switchCode: string;
  objectText: string;
  classified: Classified | null;
}

/** Build the unique room code ("0.01k") from a FLOOR_ROOM_RE match. */
function roomCodeFromMatch(m: RegExpMatchArray): string {
  return `${m[1]}.${m[2]}${m[3] ?? ""}`;
}

/** Split a leaf name into floor/room + core + object, and classify the role. */
function parseLeaf(leaf: RawLeaf): ParsedLeaf | null {
  const m = leaf.name.match(FLOOR_ROOM_RE);
  if (!m) return null;
  const floor = parseInt(m[1]!, 10);
  const room = parseInt(m[2]!, 10);
  const roomCode = roomCodeFromMatch(m);
  const rest = leaf.name.slice(m[0].length).trim();
  const tokens = rest.split(/\s+/).filter(Boolean);

  // Strip trailing object-name tokens (up to 3, e.g. "status dimwaarde").
  const objectTokens: string[] = [];
  while (tokens.length > 0 && objectTokens.length < 3) {
    const last = tokens[tokens.length - 1]!;
    if (OBJECT_TOKEN_RE.test(last)) {
      objectTokens.unshift(tokens.pop()!);
    } else {
      break;
    }
  }
  const coreTokens = [...tokens];

  // A trailing switch code (after object removal) belongs to the device, not
  // its display name.
  let switchCode = "";
  const coreNoCode = [...coreTokens];
  if (coreNoCode.length > 1) {
    const last = coreNoCode[coreNoCode.length - 1]!;
    if (SWITCH_CODE_RE.test(last)) {
      switchCode = coreNoCode.pop()!;
    }
  }

  const dpt = parseDpt(leaf.dpts);
  const objectText = objectTokens.join(" ");
  const classified = classify(objectText || leaf.name, dpt);

  return {
    ...leaf,
    floor,
    room,
    roomCode,
    coreTokens,
    coreNoCode,
    switchCode,
    objectText,
    classified,
  };
}

/** Drop leading tokens of a device core that repeat the room name. */
function stripRoomPrefix(core: string[], roomName: string): string[] {
  const rt = roomName.toLowerCase().split(/\s+/).filter(Boolean);
  let i = 0;
  while (i < rt.length && i < core.length && core[i]!.toLowerCase() === rt[i]) i++;
  return core.slice(i);
}

/** Extract a multi-channel actuator range (e.g. "A1-2") from a Description such
 *  as "1.2.13 uitgang A1-2". The module id ("1.2.13") has no hyphen, so a bare
 *  digit-range match on the whole string is safe. Returns the channel text
 *  (falls back to the raw Description) or null when it drives a single output. */
function multiChannelActuator(description: string): string | null {
  if (!description || !/\d+\s*-\s*\d+/.test(description)) return null;
  const m = description.match(/[A-Za-z]*\d+\s*-\s*\d+/);
  return (m?.[0] ?? description).trim();
}

/** Pick a shading subtype from the device name text. */
function shadingSubtype(text: string): string {
  const t = text.toLowerCase();
  if (/screen/.test(t)) return "screen";
  if (/rolluik|roller|rolll?aden/.test(t)) return "roller";
  if (/gordijn|vitrage|sheer|curtain|vorhang|gardine/.test(t)) return "sheers";
  if (/markies|awning|zonneluifel|markise/.test(t)) return "awning";
  if (/lamel|jal|slat|venetian/.test(t)) return "jalousie";
  return "blind";
}

/** Longest common leading-token prefix across a set of token arrays. */
function commonPrefix(lists: string[][]): string[] {
  if (lists.length === 0) return [];
  const out: string[] = [];
  const first = lists[0]!;
  for (let i = 0; i < first.length; i++) {
    const tok = first[i]!.toLowerCase();
    if (lists.every((l) => (l[i]?.toLowerCase() ?? null) === tok)) {
      out.push(first[i]!);
    } else {
      break;
    }
  }
  return out;
}

/* ------------------------------------------------------------------ */
/*  Device reconstruction                                             */
/* ------------------------------------------------------------------ */

function floorName(n: number): string {
  if (n < 0) return n === -1 ? "Kelder" : `Kelder ${Math.abs(n)}`;
  if (n === 0) return "Begane grond";
  return `${n}e verdieping`;
}

function titleCase(s: string): string {
  return s
    .split(/\s+/)
    .map((w) => (w ? w.charAt(0).toUpperCase() + w.slice(1) : w))
    .join(" ");
}

const AUTO_TYPES = new Set(["light_switch", "light_dimmer", "rgbw_ww", "shading", "climate"]);

/** Appliance/utility names that look like a switch or dimmer by DPT but are NOT
 *  lighting hoofdfuncties: fireplace controls, fans, boilers, pumps, sockets,
 *  mirror/floor heating, fountains, ... They stay in the searchable catalog and
 *  are added manually. Only applied to light_switch/light_dimmer — shading and
 *  climate are always hoofdfuncties regardless of name.
 *
 *  Note: bare "haard"/"zwembad" are locations (e.g. "wandlamp haard", "screen
 *  zwembad") and are deliberately NOT blocked; only "openhaard" and appliance
 *  words are. */
// NOTE: "openhaard" (NL) is blocked as an appliance, but bare "haard"/"fireplace"/
// "kamin" are locations for real lights (e.g. "wandlamp haard" = wall light by the
// fireplace) and must NOT be blocked — EN/DE cannot distinguish the two.
const NON_MAIN_FUNCTION_RE =
  /(openhaard|ventilat|l[uü]ft|afzuig|abluft|abzug|extractor|exhaust|boiler|\bpomp\b|\bpump\b|pumpe|sauna|\bwtw\b|\bhrv\b|\bwrg\b|infrarood|infrared|infrarot|sproei|sprinkler|irrigat|bew[aä]sser|\bwcd\b|wandcontact|stopcontact|socket|outlet|receptacle|steckdose|spiegelverw|spiegelheiz|mirror.?heat|\bverwarming\b|\bheating\b|\bheizung\b|fontein|fountain|brunnen)/i;

const TYPE_DEFAULT_NAME: Record<string, string> = {
  light_switch: "Verlichting",
  light_dimmer: "Dimmer",
  rgbw_ww: "RGBW",
  shading: "Zonwering",
  climate: "Thermostaat",
  ac: "Airco",
};

/** Default airco mode options + visibility, mirroring app/lib/src/ac_mode_config.dart
 *  (default-visible: Koelen/snow + Verwarmen/flame).
 *
 *  `value`s are raw DPT 20.105 enum bytes sent/decoded as-is. The exact enum is
 *  UNIT-SPECIFIC: many KNX-AC gateways use Auto=0/Cool=1/Heat=2/Fan=3/Dry=4,
 *  while the official KNX DPT 20.105 uses Heat=1/Cool=3. We keep the widely-used
 *  gateway convention below and flag every imported airco via `review.acDevices`
 *  so the installer verifies these against the unit's ETS enum before use. */
const AC_MODE_OPTIONS: ReadonlyArray<Record<string, unknown>> = [
  { label: "Auto", value: 0, icon: "auto" },
  { label: "Koelen", value: 1, icon: "snow" },
  { label: "Verwarmen", value: 2, icon: "flame" },
  { label: "Ventileren", value: 3, icon: "fan" },
  { label: "Drogen", value: 4, icon: "drop" },
];
const AC_MODE_VISIBILITY: Readonly<Record<string, boolean>> = {
  auto: false,
  snow: true,
  flame: true,
  fan: false,
  drop: false,
};
/** Default fan-speed options as PERCENTAGES (DPT 5.001, 0..100 % on the wire). */
const AC_FAN_OPTIONS: ReadonlyArray<Record<string, unknown>> = [
  { label: "Uit", value: 0 },
  { label: "Laag", value: 33 },
  { label: "Middel", value: 66 },
  { label: "Hoog", value: 100 },
];

function deviceTypeFromCats(cats: Set<RoleCategory>): string | null {
  if (cats.has("shade")) return "shading";
  if (cats.has("climate")) return "climate";
  if (cats.has("rgb")) return "rgbw_ww";
  if (cats.has("dim")) return "light_dimmer";
  if (cats.has("switch")) return "light_switch";
  return null;
}

let deviceSeq = 0;
function nextId(prefix: string): string {
  deviceSeq += 1;
  return `${prefix}-knx-${Date.now().toString(36)}-${deviceSeq}`;
}

/** Build a house.json device map from a group of leaves sharing a device key. */
function buildDevice(
  type: string,
  name: string,
  ga: Record<string, string>,
  subtype?: string
): ProposedDevice | null {
  const id = nextId("dev");
  switch (type) {
    case "light_switch":
      return { id, name, type, ga };
    case "light_dimmer":
      return { id, name, type, ga };
    case "rgbw_ww":
      return { id, name, type, rgbwWw: { mode: "channels" }, ga };
    case "shading":
      return { id, name, type, subtype: subtype ?? "blind", ga };
    case "climate":
      return {
        id,
        name,
        type,
        ga,
        climate: { canHeat: true, canCool: false, userCanSwitchMode: false },
      };
    default:
      return null;
  }
}

/* ------------------------------------------------------------------ */
/*  Main entry                                                        */
/* ------------------------------------------------------------------ */

/** Map a climate object name to a house.json ClimateGA key (or null to skip). */
function classifyClimate(rest: string): string | null {
  const t = rest.toLowerCase();
  const isStatus = STATUS_RE.test(t);
  if (/gemeten|actue|\bist\b|isttemp|istwert|ruimtetemp|measured|actual|current|raumtemp/.test(t))
    return "actual_temp";
  // "gewenste temperatuur" (setpoint), but NOT "setpointverschuiving".
  if (
    /gewenst|streef|soll|desired|target|wunsch/.test(t) ||
    /setpoint(?!versch)/.test(t)
  )
    return isStatus ? "setpoint_status" : "setpoint";
  if (/\bmodus\b|\bmode\b/.test(t)) return isStatus ? "mode_status" : "mode";
  if (
    /verwarmingsmelding|warmtevraag|heat.?demand|heiz.?anforder|w[aä]rme.?anforder/.test(
      t
    )
  )
    return "heat_demand";
  if (/koelmelding|cool.?demand|k[uü]hl.?anforder/.test(t)) return "cool_demand";
  // setpointverschuiving, regelwaarde, terugkoppeling/klep, etc: not user-facing.
  return null;
}

export function parseKnxExport(xml: string): KnxImportResult {
  const leaves = collectLeaves(xml);
  const warnings: string[] = [];
  const skipped: Array<{ address: string; name: string; reason: string }> = [];

  // 1. Catalog: every meaningful address in the export (filter placeholders).
  const catalog: GaCatalogEntry[] = [];
  const seenAddr = new Set<string>();
  for (const l of leaves) {
    if (!l.address || seenAddr.has(l.address) || isNoiseName(l.name)) continue;
    seenAddr.add(l.address);
    catalog.push({
      address: l.address,
      name: l.name,
      dpt: normalizeDpt(l.dpts),
      mainGroup: l.mainGroup || undefined,
      middleGroup: l.middleGroup || undefined,
    });
  }

  // 2. Authoritative room names. The "Centraal schakelen" section labels every
  //    room as "{floor.room} {roomname}" (e.g. "0.01k kantoor"); middle-group
  //    labels of the Klimaat/AC sections do the same. Harvest both.
  const roomNameByCode = new Map<string, string>();
  const harvestRoomName = (source: string) => {
    const m = source.match(FLOOR_ROOM_RE);
    if (!m) return;
    const code = roomCodeFromMatch(m);
    const rest = source.slice(m[0].length).trim();
    if (rest && !roomNameByCode.has(code)) roomNameByCode.set(code, titleCase(rest));
  };
  for (const l of leaves) {
    if (
      /centraal|central|zentral/i.test(`${l.mainGroup} ${l.middleGroup}`) &&
      !isNoiseName(l.name)
    ) {
      harvestRoomName(l.name);
    }
  }
  for (const l of leaves) harvestRoomName(l.middleGroup);

  const review: KnxImportReview = {
    manualDevices: [],
    duplicateNames: [],
    singleDeviceRooms: [],
    unclassified: [],
    rgbwGroups: [],
    groupChannelDevices: [],
    acDevices: [],
  };

  // 3. Split leaves: climate (dedicated) vs. AC (dedicated) vs. lighting/shading
  //    vs. skipped.
  const parsed: ParsedLeaf[] = [];
  const climateLeaves: RawLeaf[] = [];
  const acLeaves: RawLeaf[] = [];
  for (const l of leaves) {
    if (isNoiseName(l.name)) continue;
    // Dedicated AC section ("AC" main group): collect for the airco path so
    // these leaves don't fall into `skipped` (they stay in the catalog too).
    if (/^ac$/i.test(l.mainGroup.trim())) {
      acLeaves.push(l);
      continue;
    }
    if (isNonDeviceSection(l.mainGroup, l.middleGroup)) {
      skipped.push({ address: l.address, name: l.name, reason: "sectie zonder apparaat" });
      continue;
    }
    if (isClimateSection(l.mainGroup)) {
      climateLeaves.push(l);
      continue;
    }
    const p = parseLeaf(l);
    if (!p) {
      skipped.push({ address: l.address, name: l.name, reason: "geen verdieping.ruimte in naam" });
      continue;
    }
    if (!p.classified) {
      skipped.push({ address: l.address, name: l.name, reason: "objecttype niet herkend" });
      review.unclassified.push({
        address: l.address,
        name: l.name,
        reason: "rol niet herkend uit naam/DPT",
      });
      continue;
    }
    parsed.push(p);
  }

  // 3b. Fallback room names via common device-core prefix (rooms not labelled
  //     in the central section).
  const byRoom = new Map<string, ParsedLeaf[]>();
  for (const p of parsed) {
    (byRoom.get(p.roomCode) ?? byRoom.set(p.roomCode, []).get(p.roomCode)!).push(p);
  }
  for (const [code, list] of byRoom) {
    if (roomNameByCode.has(code)) continue;
    const distinctCores = new Map<string, string[]>();
    for (const p of list) distinctCores.set(p.coreNoCode.join(" ").toLowerCase(), p.coreNoCode);
    const coreLists = [...distinctCores.values()];
    let roomTokens: string[];
    if (coreLists.length >= 2) {
      roomTokens = commonPrefix(coreLists);
      if (roomTokens.length === 0) roomTokens = [coreLists[0]![0] ?? code];
    } else {
      const only = coreLists[0] ?? [];
      roomTokens = only.length > 1 ? only.slice(0, 1) : [];
      review.singleDeviceRooms.push({
        name: `${code} → "${titleCase((roomTokens.length ? roomTokens : only).join(" ") || code)}"`,
        reason: `ruimtenaam afgeleid uit één device ("${only.join(" ")}")`,
      });
    }
    roomNameByCode.set(code, roomTokens.length ? titleCase(roomTokens.join(" ")) : code);
  }

  // 4. Group lighting/shading leaves into devices.
  interface DevGroup {
    floor: number;
    room: number;
    roomCode: string;
    coreNoCode: string[];
    switchCode: string;
    description: string;
    ga: Record<string, string>;
    cats: Set<RoleCategory>;
  }

  const addToGroup = (map: Map<string, DevGroup>, key: string, p: ParsedLeaf) => {
    let g = map.get(key);
    if (!g) {
      g = {
        floor: p.floor,
        room: p.room,
        roomCode: p.roomCode,
        coreNoCode: p.coreNoCode,
        switchCode: p.switchCode,
        description: p.description,
        ga: {},
        cats: new Set(),
      };
      map.set(key, g);
    }
    if (!p.classified) return;
    g.cats.add(p.classified.cat);
    // gaKey "" only signals the category (e.g. relative dim), stores no address.
    if (p.classified.gaKey && g.ga[p.classified.gaKey] === undefined) {
      g.ga[p.classified.gaKey] = p.address;
    }
  };

  // 4a. RGB(W): color channels of one fixture live on SEPARATE actuator
  //     channels, so group them by name-core (color word excluded) instead.
  const rgbGroups = new Map<string, ParsedLeaf[]>();
  const nonColor: ParsedLeaf[] = [];
  for (const p of parsed) {
    if (p.classified?.cat === "rgb") {
      const key = `${p.roomCode}|${p.coreNoCode.join(" ").toLowerCase()}`;
      (rgbGroups.get(key) ?? rgbGroups.set(key, []).get(key)!).push(p);
    } else {
      nonColor.push(p);
    }
  }

  // 4b. Non-color lighting/shading: group by the physical actuator channel
  //     (Description). This merges on/off + dim + value + status of one output,
  //     and — crucially — keeps two identically-named outputs apart. Falls back
  //     to name+code when no Description is present.
  const groups = new Map<string, DevGroup>();
  for (const p of nonColor) {
    const key = p.description
      ? `desc|${p.description.toLowerCase()}`
      : `name|${p.roomCode}|${p.coreTokens.join(" ").toLowerCase()}`;
    addToGroup(groups, key, p);
  }

  // 5. Build floors -> rooms -> devices proposal.
  const floorMap = new Map<number, ProposedFloor>();
  let deviceCount = 0;
  const roomSet = new Set<string>();

  const ensureRoom = (
    floorNum: number,
    roomNum: number,
    roomCode: string
  ): ProposedRoom => {
    let floor = floorMap.get(floorNum);
    if (!floor) {
      floor = { floor: floorNum, name: floorName(floorNum), rooms: [] };
      floorMap.set(floorNum, floor);
    }
    let room = floor.rooms.find((r) => r.code === roomCode);
    if (!room) {
      room = {
        code: roomCode,
        floor: floorNum,
        room: roomNum,
        name: roomNameByCode.get(roomCode) ?? roomCode,
        devices: [],
      };
      floor.rooms.push(room);
      roomSet.add(roomCode);
    }
    return room;
  };

  /** Append a device, making its name unique within the room. */
  const addDevice = (
    room: ProposedRoom,
    device: ProposedDevice,
    switchCode: string,
    primaryGa: string
  ) => {
    const baseName = String(device["name"]);
    if (room.devices.some((d) => d["name"] === device["name"])) {
      let suffix = switchCode;
      if (!suffix) {
        let n = 2;
        while (room.devices.some((d) => d["name"] === `${baseName} ${n}`)) n++;
        suffix = String(n);
      }
      device["name"] = `${baseName} ${suffix}`;
      review.duplicateNames.push({
        address: primaryGa,
        name: `${room.name} — ${device["name"]}`,
        reason: "dubbele naam in ruimte, automatisch onderscheiden",
      });
    }
    room.devices.push(device);
    deviceCount += 1;
  };

  for (const g of groups.values()) {
    const type = deviceTypeFromCats(g.cats);
    if (!type || !AUTO_TYPES.has(type)) continue; // catalog only
    // A dimmer needs an absolute value GA to be steerable; without one, treat
    // it as a plain switch (still has switch/switch_status).
    let finalType = type;
    if (type === "light_dimmer" && g.ga["dim_value"] === undefined) {
      finalType = "light_switch";
    }

    const roomName = roomNameByCode.get(g.roomCode) ?? g.roomCode;
    const nameTokens = stripRoomPrefix(g.coreNoCode, roomName);
    let devName = titleCase(nameTokens.join(" ").trim());
    if (!devName) devName = TYPE_DEFAULT_NAME[finalType] ?? "Apparaat";
    const primaryGa = Object.values(g.ga)[0] ?? "";

    // Non-lighting appliances (only among on/off & dim devices): keep in the
    // catalog, list for manual review, do not auto-create.
    if (
      (finalType === "light_switch" || finalType === "light_dimmer") &&
      NON_MAIN_FUNCTION_RE.test(g.coreNoCode.join(" "))
    ) {
      review.manualDevices.push({
        address: primaryGa,
        name: `${roomName} — ${devName}`,
        reason: "geen verlichtings-hoofdfunctie (bv. stopcontact/verwarming/pomp)",
      });
      continue;
    }

    // A shading device needs an up/down address to be steerable. Without one
    // (only stop/position/slat), don't auto-create it: flag for manual review.
    if (finalType === "shading" && g.ga["up_down"] === undefined) {
      review.manualDevices.push({
        address: primaryGa,
        name: `${roomName} — ${devName}`,
        reason: "zonwering zonder op/neer-adres — controleer handmatig",
      });
      continue;
    }

    const subtype =
      finalType === "shading" ? shadingSubtype(g.coreNoCode.join(" ")) : undefined;
    const device = buildDevice(finalType, devName, g.ga, subtype);
    if (!device) continue;

    const room = ensureRoom(g.floor, g.room, g.roomCode);
    addDevice(room, device, g.switchCode, primaryGa);

    // Group-GA signalering: one GA that drives multiple actuator contacts
    // (Description spans a channel range, e.g. "A1-2"). Lighting only — a
    // jalousie normally uses two relays ("A1-2"), so shading would be a false
    // positive. Purely additive: the device is still imported normally.
    if (finalType === "light_switch" || finalType === "light_dimmer") {
      const channel = multiChannelActuator(g.description);
      if (channel) {
        review.groupChannelDevices.push({
          address: primaryGa,
          name: `${roomName} — ${String(device["name"])}`,
          reason: `groeps-GA: stuurt meerdere contacten samen aan (${channel})`,
        });
      }
    }
  }

  // 5b. RGB(W) devices from validated color groups.
  for (const list of rgbGroups.values()) {
    const first = list[0]!;
    const ga: Record<string, string> = {};
    for (const p of list) {
      const k = p.classified!.gaKey;
      if (k && ga[k] === undefined) ga[k] = p.address;
    }
    const hasRGB = ga["r"] && ga["g"] && ga["b"];
    const hasCCT = ga["ww"] && ga["cw"];
    const roomName = roomNameByCode.get(first.roomCode) ?? first.roomCode;
    const devName =
      titleCase(stripRoomPrefix(first.coreNoCode, roomName).join(" ").trim()) ||
      TYPE_DEFAULT_NAME["rgbw_ww"]!;
    if (hasRGB || hasCCT) {
      const device = buildDevice("rgbw_ww", devName, ga);
      if (device) {
        const room = ensureRoom(first.floor, first.room, first.roomCode);
        addDevice(room, device, first.switchCode, Object.values(ga)[0] ?? "");
        review.rgbwGroups.push({
          address: Object.values(ga)[0] ?? "",
          name: `${roomName} — ${devName}`,
          reason: `kleurkanalen samengevoegd: ${Object.keys(ga).join("/")}`,
        });
      }
    } else {
      // Not enough channels for a real RGB/CCT fixture (likely a plain white
      // lamp mislabeled). Re-route each leaf as normal lighting.
      for (const p of list) {
        const dpt = parseDpt(p.dpts);
        const isStatus = STATUS_RE.test(p.objectText.toLowerCase());
        let role: Classified | null = null;
        if (dpt?.main === 5) role = { gaKey: isStatus ? "dim_status" : "dim_value", cat: "dim" };
        else if (dpt?.main === 3) role = { gaKey: "", cat: "dim" };
        else if (dpt?.main === 1) role = { gaKey: isStatus ? "switch_status" : "switch", cat: "switch" };
        if (!role) continue;
        p.classified = role;
        const key = p.description
          ? `desc|${p.description.toLowerCase()}`
          : `name|${p.roomCode}|${p.coreTokens.join(" ").toLowerCase()}`;
        const map = new Map<string, DevGroup>();
        addToGroup(map, key, p);
        for (const g of map.values()) {
          const t = deviceTypeFromCats(g.cats);
          if (!t) continue;
          const roomName2 = roomNameByCode.get(g.roomCode) ?? g.roomCode;
          const dn =
            titleCase(stripRoomPrefix(g.coreNoCode, roomName2).join(" ").trim()) ||
            TYPE_DEFAULT_NAME[t] ||
            "Apparaat";
          const dev = buildDevice(t, dn, g.ga);
          if (!dev) continue;
          const room = ensureRoom(g.floor, g.room, g.roomCode);
          addDevice(room, dev, g.switchCode, Object.values(g.ga)[0] ?? "");
        }
      }
    }
  }

  // 6. Climate: exactly one thermostat per room from the Klimaat section.
  const climateByRoom = new Map<
    string,
    { floor: number; room: number; roomCode: string; ga: Record<string, string> }
  >();
  for (const l of climateLeaves) {
    const m = l.name.match(FLOOR_ROOM_RE);
    if (!m) continue;
    const rest = l.name.slice(m[0].length).trim();
    const key = classifyClimate(rest);
    if (!key) continue;
    const roomCode = roomCodeFromMatch(m);
    let e = climateByRoom.get(roomCode);
    if (!e) {
      e = { floor: parseInt(m[1]!, 10), room: parseInt(m[2]!, 10), roomCode, ga: {} };
      climateByRoom.set(roomCode, e);
    }
    if (e.ga[key] === undefined) e.ga[key] = l.address;
  }
  for (const e of climateByRoom.values()) {
    // A thermostat needs both the measured and the desired temperature to be
    // usable. If only one is present, don't auto-create it: flag for review.
    if (e.ga["actual_temp"] === undefined || e.ga["setpoint"] === undefined) {
      if (e.ga["actual_temp"] !== undefined || e.ga["setpoint"] !== undefined) {
        review.manualDevices.push({
          address: Object.values(e.ga)[0] ?? "",
          name: `${roomNameByCode.get(e.roomCode) ?? e.roomCode} — ${TYPE_DEFAULT_NAME["climate"]}`,
          reason:
            "klimaat onvolledig (mist gemeten- of gewenste temperatuur) — controleer handmatig",
        });
      }
      continue;
    }
    const device = buildDevice("climate", TYPE_DEFAULT_NAME["climate"]!, e.ga);
    if (!device) continue;
    const room = ensureRoom(e.floor, e.room, e.roomCode);
    room.devices.push(device);
    deviceCount += 1;
  }

  // 7. Airco: one `ac` device per room from the dedicated "AC" section. Uses the
  //    app's `ac` type (onOff/setpoint/mode/fanSpeed), NOT `climate`.
  interface AcSlot {
    ga?: string;
    statusGa?: string;
  }
  interface AcAccum {
    floor: number;
    room: number;
    roomCode: string;
    onOff: AcSlot;
    setpoint: AcSlot;
    mode: AcSlot;
    fanSpeed: AcSlot;
  }
  const acByRoom = new Map<string, AcAccum>();
  for (const l of acLeaves) {
    const m = l.name.match(FLOOR_ROOM_RE);
    if (!m) continue;
    const roomCode = roomCodeFromMatch(m);
    const rest = l.name.slice(m[0].length).trim().toLowerCase();
    // Skip objects the `ac` type has no slot for / that are not room controls.
    // DPT 1.100 cool/heat toggle: NL "koelen/verwarmen" | EN | DE.
    if (/(koelen\s*\/\s*verwarmen|cool(ing)?\s*\/\s*heat(ing)?|k[uü]hlen\s*\/\s*heizen)/.test(rest))
      continue;
    // auto-fan toggle
    if (/(ventilator|fan|l[uü]fter)\s+(automat|auto)/.test(rest)) continue;
    // external reference temperature
    if (/externe?|referentie|reference|referenz/.test(rest)) continue;
    let e = acByRoom.get(roomCode);
    if (!e) {
      e = {
        floor: parseInt(m[1]!, 10),
        room: parseInt(m[2]!, 10),
        roomCode,
        onOff: {},
        setpoint: {},
        mode: {},
        fanSpeed: {},
      };
      acByRoom.set(roomCode, e);
    }
    const isStatus = STATUS_RE.test(rest);
    const assign = (slot: AcSlot) => {
      if (isStatus) {
        if (slot.statusGa === undefined) slot.statusGa = l.address;
      } else if (slot.ga === undefined) {
        slot.ga = l.address;
      }
    };
    if (/ventilatorsnelheid|ventilatorstufe|fan\s*speed|fanspeed|l[uü]ftergeschwindigkeit/.test(rest))
      assign(e.fanSpeed);
    else if (/\bmodus\b|\bmode\b/.test(rest)) assign(e.mode);
    else if (/gewenst|desired|target|soll|wunsch|setpoint/.test(rest))
      assign(e.setpoint);
    else if (/aan\s*\/\s*uit|on\s*\/\s*off|ein\s*\/\s*aus/.test(rest))
      assign(e.onOff);
  }
  for (const e of acByRoom.values()) {
    const roomName = roomNameByCode.get(e.roomCode) ?? e.roomCode;
    // Schema minimum for `ac`: both onOff.ga and setpoint.ga must be present.
    if (e.onOff.ga === undefined || e.setpoint.ga === undefined) {
      review.manualDevices.push({
        address: e.onOff.ga ?? e.setpoint.ga ?? "",
        name: `${roomName} — ${TYPE_DEFAULT_NAME["ac"]}`,
        reason:
          "airco onvolledig (mist aan/uit of gewenste temperatuur) — controleer handmatig",
      });
      continue;
    }
    const ac: Record<string, unknown> = {
      onOff: {
        ga: e.onOff.ga,
        ...(e.onOff.statusGa ? { statusGa: e.onOff.statusGa } : {}),
      },
      setpoint: {
        ga: e.setpoint.ga,
        ...(e.setpoint.statusGa ? { statusGa: e.setpoint.statusGa } : {}),
      },
    };
    if (e.mode.ga !== undefined) {
      ac["mode"] = {
        ga: e.mode.ga,
        ...(e.mode.statusGa ? { statusGa: e.mode.statusGa } : {}),
        options: AC_MODE_OPTIONS,
      };
    }
    if (e.fanSpeed.ga !== undefined) {
      ac["fanSpeed"] = {
        ga: e.fanSpeed.ga,
        ...(e.fanSpeed.statusGa ? { statusGa: e.fanSpeed.statusGa } : {}),
        options: AC_FAN_OPTIONS,
      };
    }
    ac["modeVisibility"] = AC_MODE_VISIBILITY;
    const device: ProposedDevice = {
      id: nextId("dev"),
      name: TYPE_DEFAULT_NAME["ac"]!,
      type: "ac",
      ac,
    };
    const room = ensureRoom(e.floor, e.room, e.roomCode);
    room.devices.push(device);
    deviceCount += 1;
    review.acDevices.push({
      address: e.onOff.ga,
      name: `${roomName} — ${TYPE_DEFAULT_NAME["ac"]}`,
      reason:
        "controleer modus-/ventilatorwaarden (DPT 20.105 / 5.001) tegen de ETS-enum van de unit; bus-encoding mogelijk aan te passen",
    });
  }

  const floors = [...floorMap.values()].sort((a, b) => a.floor - b.floor);
  for (const f of floors) {
    f.rooms.sort((a, b) => a.room - b.room || a.code.localeCompare(b.code));
  }

  return {
    catalog,
    floors,
    skipped,
    warnings,
    review,
    stats: {
      addresses: catalog.length,
      devices: deviceCount,
      floors: floors.length,
      rooms: roomSet.size,
      manual: review.manualDevices.length,
      unclassified: review.unclassified.length,
      groupChannel: review.groupChannelDevices.length,
      ac: review.acDevices.length,
    },
  };
}

/* ------------------------------------------------------------------ */
/*  Catalog persistence                                              */
/* ------------------------------------------------------------------ */

export function persistGaCatalog(catalog: GaCatalogEntry[]): void {
  const tmp = `${catalogPath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ catalog }, null, 2), "utf-8");
  fs.renameSync(tmp, catalogPath);
}

export function loadGaCatalog(): GaCatalogEntry[] {
  try {
    const raw = fs.readFileSync(catalogPath, "utf-8");
    const parsed = JSON.parse(raw) as { catalog?: GaCatalogEntry[] };
    return Array.isArray(parsed.catalog) ? parsed.catalog : [];
  } catch {
    return [];
  }
}
