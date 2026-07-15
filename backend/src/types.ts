export type GA = string; // "x/y/z"

export type DeviceType =
  | "light_switch"
  | "light_dimmer"
  | "rgbw_ww"
  | "shading"
  | "position_actuator"
  | "climate"
  | "media_sonos"
  | "media_bluesound"
  | "camera"
  | "intercom"
  | "fireplace"
  | "ac"
  | "fan"
  | "universal"
  | "lutron_homeworks";

/**
 * Lutron Homeworks-load via #OUTPUT (integration ID uit Lutron integration report).
 * Telnet staat op `house.lutron`; optioneel legacy `homeworksDeviceId` voor oudere configs.
 */
export interface LutronLoadOutputBinding {
  integrationId: number;
  loadType: "dimmer" | "switch" | "shade";
  /** Fade in seconden bij set level (optioneel). */
  fadeSeconds?: number;
  /** Legacy: apart `lutron_homeworks`-apparaat als gateway. */
  homeworksDeviceId?: string;
}

export interface LightSwitchGA {
  switch?: GA;
  switch_status?: GA;
}

export interface LightDimmerGA extends LightSwitchGA {
  dim_value?: GA;
  dim_status?: GA;
}

export interface ShadingGA {
  up_down: GA;
  stop_step?: GA;
  position?: GA;
  position_status?: GA;
  slat?: GA;
  slat_status?: GA;
  /** DPT 1.x — 1 while the shade is moving; UI may blink the status icon. */
  moving?: GA;
}

/** Visual/functional variant of a shading device.
 *  - `blind`:    horizontal/vertical blinds w/ slat tilt (typical KNX jalousie)
 *  - `roller`:   roller shutter (position only, no slats)
 *  - `curtain`:  curtains/drapes (icon change only, same commands)
 *  - `jalousie`: same as `blind` but explicitly exposes a slats slider
 *                even when a dedicated slat GA isn't set (fallback 0..100).
 *  - `screen`:   zip/ritsscreen (vertical)
 *  - `sheers`:   inbetween gordijn / vitrage (horizontal like curtain)
 *  - `awning`:   markies (angled) */
export type ShadingSubtype =
  | "blind"
  | "roller"
  | "curtain"
  | "jalousie"
  | "screen"
  | "sheers"
  | "awning";

export interface ClimateGA {
  /** DPT 9.001 - gemeten temperatuur (lezen). */
  actual_temp: GA;
  /** DPT 9.001 - gewenste temperatuur (schrijven). */
  setpoint: GA;
  /** DPT 9.001 - gewenste temperatuur status (lezen, optioneel). */
  setpoint_status?: GA;
  /** DPT 20.102 - HVAC-modus (schrijven). */
  mode?: GA;
  /** DPT 20.102 - HVAC-modus status (lezen). */
  mode_status?: GA;
  /**
   * DPT 1.100 (Heat/Cool) - schrijven: 1 = verwarmen, 0 = koelen.
   * Alleen zichtbaar als userCanSwitchMode: true.
   */
  hvac_mode?: GA;
  /** DPT 1.100 - lezen: huidige verwarm/koel-modus van het systeem. */
  hvac_mode_status?: GA;
  /** DPT 1.x - melding: ruimte vraagt actief om warmte. */
  heat_demand?: GA;
  /** DPT 1.x - melding: ruimte vraagt actief om koude. */
  cool_demand?: GA;
}

/** A single confirmation prompt that the UI shows before firing a command.
 *  Pass `true` for the default copy, or a string for a custom message. */
export type ConfirmPrompt =
  | boolean
  | string
  | {
      title?: string;
      message?: string;
      /** 4-digit PIN the user must enter before the action fires. */
      pin?: string;
    };

/** Per-device opt-in for "are you sure?" dialogs. Backend is just the
 *  config carrier — actually showing the dialog is a Flutter concern. */
export interface DeviceConfirm {
  /** Confirm before turning the device ON / running its main action
   *  (open door, start fireplace, etc.). */
  on?: ConfirmPrompt;
  /** Confirm before turning the device OFF. */
  off?: ConfirmPrompt;
  /** Per-button / per-action override (keyed by button id for universal
   *  devices, or by `"release"` / `"doorbell"` for intercom). */
  actions?: Record<string, ConfirmPrompt>;
}

export interface DeviceBase {
  id: string;
  name: string;
  favorite?: boolean;
  /** Ask the user to confirm potentially disruptive commands. */
  confirm?: DeviceConfirm;
}

export interface LightSwitchDevice extends DeviceBase {
  type: "light_switch";
  /** Standaard `knx`. Met `lutron` worden commando’s naar Lutron #OUTPUT gestuurd i.p.v. KNX. */
  control?: "knx" | "lutron";
  /** Lutron output integration ID (project → Lutron). */
  lutronIntegrationId?: number;
  /** Legacy; gebruik `lutronIntegrationId`. */
  lutronOutput?: LutronLoadOutputBinding;
  ga: LightSwitchGA;
}

export interface LightDimmerDevice extends DeviceBase {
  type: "light_dimmer";
  control?: "knx" | "lutron";
  lutronIntegrationId?: number;
  lutronOutput?: LutronLoadOutputBinding;
  ga: LightDimmerGA;
}

/** KNX DPT 232.600 RGB triplet (red/green/blue 0–255). */
export interface Rgb232Triplet {
  red: number;
  green: number;
  blue: number;
}

/**
 * RGB / warmwit / koudwit driver.
 *
 * Modes:
 * - `channels`       : aparte GA per kanaal (r/g/b/w/ww/cw), DPT 5.010 (0–255).
 * - `composite`      : één GA, ruwe APDU (`writeRaw`), standaard 14 bytes.
 * - `rgb232`         : één GA, DPT 232.600 (3 bytes R·G·B, elk 0–255).
 * - `tunable_white`  : kleurtemperatuur via twee GA's: `ww` (warm) + `cw` (koud),
 *                      én/of `bright` (helderheid) + `kelvin` (DPT 9.001, bijv. 2700–6500 K).
 *
 * Kanaal-detectie in `channels`-modus:
 * - r+g+b aanwezig  → kleurenwiel + helderheidsschuif
 * - r+g+b+w         → kleurenwiel + witte kanaalschuif
 * - r+g+b+ww/cw     → kleurenwiel + CCT-schuif
 * - alleen ww/cw    → CCT-picker
 */
export interface RgbwWwGA {
  /** Aan/uit schakelaar (DPT 1.001, optioneel). */
  on?: GA;
  r?: GA;
  g?: GA;
  b?: GA;
  /** Onafhankelijk wit kanaal (DPT 5.010). */
  w?: GA;
  /** Warmwit kanaal (DPT 5.010). */
  ww?: GA;
  /** Koudwit kanaal (DPT 5.010). */
  cw?: GA;
  /** `mode: "composite"` */
  composite?: GA;
  /** `mode: "rgb232"` — DPT 232.600 */
  rgb232?: GA;
  /** `mode: "tunable_white"` — helderheid GA (DPT 5.010, 0–255). */
  bright?: GA;
  /**
   * `mode: "tunable_white"` — kleurtemperatuur GA (DPT 9.001, Kelvin).
   * Typisch 2700–6500 K.
   */
  kelvin?: GA;
}

export interface RgbwWwConfig {
  mode: "channels" | "composite" | "rgb232" | "tunable_white";
  /** Telegramlengte voor `composite` (1–14, standaard 14). */
  payloadBytes?: number;
  /** `tunable_white`: minimale Kelvin-waarde (standaard 2700). */
  kelvinMin?: number;
  /** `tunable_white`: maximale Kelvin-waarde (standaard 6500). */
  kelvinMax?: number;
}

export interface RgbwWwDevice extends DeviceBase {
  type: "rgbw_ww";
  ga: RgbwWwGA;
  rgbwWw: RgbwWwConfig;
}

export interface ShadingUi {
  /** Position (0–100 %) slider; requires `ga.position`. */
  showPositionSlider?: boolean;
  /** Up / open move command. */
  showMoveUp?: boolean;
  /** Stop / step (uses `stop_step` GA). */
  showMoveStop?: boolean;
  /** Down / close move command. */
  showMoveDown?: boolean;
  /** When a position slider is shown, also show the move button row below it. */
  showMoveButtonsUnderSlider?: boolean;
  /** Lamellen / slat tilt slider. */
  showSlatSlider?: boolean;
  /** Lamellen in kleine stappen (±5 %) via `ga.slat`. */
  showSlatStepButtons?: boolean;
}

export interface ShadingDevice extends DeviceBase {
  type: "shading";
  /** Visual variant (default `"blind"`). Drives icon + whether the
   *  slat slider is rendered. */
  subtype?: ShadingSubtype;
  /** Prefer a continuous position slider over up/down/stop buttons
   *  when the driver exposes `ga.position`. Defaults to `true`. */
  slider?: boolean;
  /** Which controls appear in the customer app (installateur vinkt aan/uit). */
  shadingUi?: ShadingUi;
  control?: "knx" | "lutron";
  lutronIntegrationId?: number;
  /** Lutron output integration ID voor lamelhoek (tilt), apart van de positie. */
  lutronSlatIntegrationId?: number;
  lutronOutput?: LutronLoadOutputBinding;
  ga: ShadingGA;
}

/** Percentage-aansturing via KNX jaloezie-object (kleppen, ramen, …). */
export interface PositionActuatorDevice extends DeviceBase {
  type: "position_actuator";
  /** Prefer a continuous position slider over up/down/stop buttons
   *  when the driver exposes `ga.position`. Defaults to `true`. */
  slider?: boolean;
  /** Which controls appear in the customer app (same keys as shading). */
  shadingUi?: ShadingUi;
  ga: ShadingGA;
}

/** Optionele capabilities-configuratie voor het klimaatapparaat. */
export interface ClimateModeVisibility {
  comfort?: boolean;
  standby?: boolean;
  economy?: boolean;
  buildingProtection?: boolean;
}

export interface ClimateConfig {
  /** Systeem kan verwarmen (standaard: true). */
  canHeat?: boolean;
  /** Systeem kan koelen (standaard: false). */
  canCool?: boolean;
  /**
   * Gebruiker mag zelf schakelen. Als false: alleen status-indicatie,
   * geen schakelknop in de app.
   */
  userCanSwitchMode?: boolean;
  /**
   * Hoe lang de omschakelknop na gebruik geblokkeerd blijft.
   * Formaat "u:mm" (bijv. "4:00"). "0:00" = geen blokkade, wel waarschuwing.
   */
  hvacSwitchLockDuration?: string;
  /** Minimum instelbare temperatuur in °C (standaard 5). */
  minTemp?: number;
  /** Maximum instelbare temperatuur in °C (standaard 35). */
  maxTemp?: number;
  /** Stapgrootte voor setpoint aanpassing (0.1, 0.5 of 1.0, standaard 0.5). */
  tempStep?: 0.1 | 0.5 | 1.0;
  /** Per bedrijfsmodus aan/uit (DPT 20.102). false = niet zichtbaar in app. */
  modes?: ClimateModeVisibility;
}

export interface ClimateDevice extends DeviceBase {
  type: "climate";
  ga: ClimateGA;
  /** Optionele capabilities/weergave-instellingen. */
  climate?: ClimateConfig;
}

/* --------------------------------------------------------------------- */
/*  Media players                                                        */
/* --------------------------------------------------------------------- */

export interface SonosConfig {
  /** IP or DNS of the zone coordinator. Leave undefined + set `room` to
   *  resolve via SSDP discovery on boot (best-effort). */
  host?: string;
  /** SOAP port, default 1400. Only override for Sonos simulators. */
  port?: number;
  /** Sonos zone/room name as configured in the Sonos app. Used for
   *  discovery fallback when `host` isn't set. */
  room?: string;
  /** Spotify Connect device name for this zone, if it differs from the
   *  device `name`/`room`. Used to target playback via Spotify Connect. */
  spotifyDeviceName?: string;
}

export interface SonosDevice extends DeviceBase {
  type: "media_sonos";
  sonos: SonosConfig;
}

export interface BluesoundConfig {
  host: string;
  /** BluOS HTTP port, default 11000. */
  port?: number;
  /** Spotify Connect device name for this player, if it differs from the
   *  device `name`. Used to target playback via Spotify Connect. */
  spotifyDeviceName?: string;
}

export interface BluesoundDevice extends DeviceBase {
  type: "media_bluesound";
  bluesound: BluesoundConfig;
}

/** Transport state shared by every media player tile. */
export type MediaTransport = "playing" | "paused" | "stopped" | "buffering";

/** A playable preset (Sonos favourite or Bluesound preset slot). */
export interface MediaPreset {
  id: string;
  name: string;
  /** Optional small artwork thumbnail URL (as served by the device). */
  image?: string;
  /** Content URI — used for direct playback (more reliable than name lookup). */
  uri?: string;
}

/** Unified snapshot of a media player, broadcast over the WS channel. */
export interface MediaState {
  deviceId: string;
  /** `"sonos"` or `"bluesound"` — lets the UI pick iconography. */
  brand: "sonos" | "bluesound";
  online: boolean;
  transport: MediaTransport;
  title?: string;
  artist?: string;
  album?: string;
  /** URL that the app can fetch directly (camera-like passthrough is
   *  unnecessary; Sonos/BluOS art URLs are served over plain HTTP). */
  albumArt?: string;
  /** Current source label, e.g. "Spotify" or "Radio Paradise". */
  source?: string;
  /** 0..100 volume. Null means "unknown" (device offline). */
  volume?: number;
  muted?: boolean;
  /** Position/duration in seconds (best effort — not all streams report). */
  position?: number;
  duration?: number;
  /** ISO timestamp of the last successful poll. */
  lastUpdate?: string;
  /** Raw content URI of the currently playing item (for artwork fallback). */
  currentUri?: string;
  /** Cached preset list so the UI can render the picker without a
   *  follow-up request. */
  presets?: MediaPreset[];
  /** Zone grouping state. Only present when actively tracked. */
  groupRole?: "coordinator" | "member" | "standalone";
  /** IDs of member zones (only set when role = coordinator). */
  groupMemberIds?: string[];
  /** ID of the coordinator zone (only set when role = member). */
  groupCoordinatorId?: string;
}

/** A normalized, directly-playable search hit. */
export interface MediaSearchResult {
  /** Stable id for the UI list (we use the playRef). */
  id: string;
  kind: "track" | "album" | "artist" | "playlist" | "radio" | "favorite";
  title: string;
  subtitle?: string;
  /** Proxied artwork URL (served via /api/media-art). */
  image?: string;
  /** Brand-specific playable reference: Sonos content URI or BluOS playURL. */
  playRef: string;
}

/** A group of results under a heading (e.g. "Favorieten", "Spotify"). */
export interface MediaSearchSection {
  title: string;
  results: MediaSearchResult[];
}

export interface CameraConfig {
  rtsp: string;
  /** Optioneel: korte naam voor go2rtc (a-z, 0-9, streepje). Leeg of alleen spaties = afgeleid van apparaat-id (niet `""` in JSON). */
  path?: string;
  aspect?: string;
  codec?: "h264" | "h265";
  republish?: boolean;
  directHls?: string;
  /** Optional lower-res RTSP for fast thumbnails; live uses `rtsp`. */
  previewRtsp?: string;
  sources?: string[];
  /** go2rtc native RTSP: append `#media=video` (skips odd audio; helps WebRTC/HLS). */
  go2rtcVideoOnly?: boolean;
  /** go2rtc native RTSP: append `#backchannel=0` for glitchy view-only NVRs. */
  go2rtcBackchannel0?: boolean;
  /** With `go2rtcFfmpeg`, transcode live to H264 with short GOP (Synology / fragile RTSP). */
  go2rtcFfmpeg?: boolean;
  /** Legacy UI flag; go2rtc uses RTSP/TCP by default (no extra fragment needed). */
  go2rtcRtspTcp?: boolean;
}

export interface CameraDevice extends DeviceBase {
  type: "camera";
  camera: CameraConfig;
}

export type IntercomKind = "doorbird" | "twoN" | "sip";

/** SIP WebSocket-registratie (Asterisk / FreePBX); wachtwoord blijft op de server. */
export interface IntercomSipConfig {
  webSocketUrl?: string;
  uri?: string;
  authorizationUser?: string;
  password?: string;
  displayName?: string;
}

export type IntercomReleaseMode = "knx" | "doorbird";

/** DoorBird LAN-API (open-door.cgi); credentials blijven op de server in house.json. */
export interface IntercomDoorbirdConfig {
  host: string;
  port?: number;
  /** HTTPS (poort 443 standaard); LAN-certificaat is zelfondertekend. */
  useTls?: boolean;
  /** Bij `useTls`: negeer TLS-certificaatfouten (aanbevolen op LAN). Standaard true. */
  insecureTls?: boolean;
  username: string;
  password: string;
  /** Query-parameter `r` voor open-door (bijv. "1", "2"). Standaard "1". */
  relay?: string;
}

export interface IntercomConfig {
  /** Fabrikant / gesprekskanaal — geen KNX. */
  kind?: IntercomKind;
  rtsp: string;
  path?: string;
  aspect?: string;
  codec?: "h264" | "h265";
  sources?: string[];
  doorbell?: { ga: GA };
  /** Standaard KNX als `release.ga` gezet is; expliciet voor DoorBird-only. */
  releaseMode?: IntercomReleaseMode;
  release?: {
    ga: GA;
    pulseMs?: number;
  };
  doorbird?: IntercomDoorbirdConfig;
  sip?: IntercomSipConfig;
  /**
   * Optionele passcode voor de HTTP ring-webhook (`POST /api/webhooks/ring/:id`).
   * Configureer dezelfde code in DoorBird / 2N als webhook-URL-parameter `passcode`.
   * Leeg laten = webhook accepteert elke aanroep (alleen op vertrouwd LAN).
   */
  webhookPasscode?: string;
}

export interface IntercomDevice extends DeviceBase {
  type: "intercom";
  intercom: IntercomConfig;
}

/* --------------------------------------------------------------------- */
/*  Fireplace — analog (switch + level) or discrete (pulse contacts)        */
/* --------------------------------------------------------------------- */

/** Single push-button style KNX object (DPT1 pulse). */
export interface FireplacePulseChannel {
  ga: GA;
  /** True then false after this many ms (default 250). */
  pulseMs?: number;
}

/** Level control via separate contacts (aan/uit/hoger/lager). */
export interface FireplaceDiscreteLevel {
  on?: FireplacePulseChannel;
  off?: FireplacePulseChannel;
  up?: FireplacePulseChannel;
  down?: FireplacePulseChannel;
}

export interface FireplaceConfig {
  /**
   * `analog` = schakel + slider (percent of 0–10 V / 0–3 V weergave op de bus als DPT5).
   * `discrete` = pulscommando’s op aparte GA’s voor aan, uit, hoger, lager.
   */
  controlMode?: "analog" | "discrete";
  onOff: { ga: GA; statusGa?: GA };
  flame?: {
    ga: GA;
    statusGa?: GA;
    /** If set, the slider snaps between `1..steps` (discrete DPT5.010 bytes).
     *  If unset, the flame is modelled as a 0..100 percent (DPT5.001). */
    steps?: number;
    /** UI only: slider labels as % or estimated volts (bus value still 0..100). */
    levelDisplay?: "percent" | "volt_10" | "volt_3";
    /**
     * Percent bands per visible step (1..N). When present, the bus uses DPT5.001
     * (0–100 %): selecting step k sends `write` or midpoint of [min,max].
     * `steps` should equal `stepRanges.length` (enforced in validation).
     */
    stepRanges?: { min: number; max: number; write?: number }[];
  };
  discreteLevel?: FireplaceDiscreteLevel;
  safetyLockout?: { ga: GA };
}

export interface FireplaceDevice extends DeviceBase {
  type: "fireplace";
  fireplace: FireplaceConfig;
}

/* --------------------------------------------------------------------- */
/*  Air conditioning — on/off, setpoint, mode, fan speed                 */
/* --------------------------------------------------------------------- */

export interface AcModeOption {
  label: string;
  value: number;
  icon?: string;
}

export interface AcConfig {
  onOff: { ga: GA; statusGa?: GA };
  setpoint: { ga: GA; statusGa?: GA; min?: number; max?: number };
  actualTemp?: { ga: GA };
  mode?: {
    ga: GA;
    statusGa?: GA;
    options: AcModeOption[];
  };
  fanSpeed?: {
    ga: GA;
    statusGa?: GA;
    options: AcModeOption[];
  };
  /** Gebruiker mag zelf omschakelen tussen verwarmen/koelen. */
  userCanSwitchMode?: boolean;
  /** Vergrendelduur na omschakelen (`u:mm`, bijv. `0:02`). */
  hvacSwitchLockDuration?: string;
  /**
   * Per modus zichtbaar in app (sleutel = icon, bijv. `snow`, `flame`, `auto`).
   * Ontbreekt een sleutel: standaard alleen koelen/verwarmen zichtbaar.
   */
  modeVisibility?: Record<string, boolean>;
}

export interface AcDevice extends DeviceBase {
  type: "ac";
  ac: AcConfig;
}

/* --------------------------------------------------------------------- */
/*  Fan — on/off + speed + optional oscillate/direction                  */
/* --------------------------------------------------------------------- */

export interface FanConfig {
  onOff: { ga: GA; statusGa?: GA };
  speed?: {
    ga: GA;
    statusGa?: GA;
    /**
     * Aansturingsmodus:
     * - `steps`   : discrete standen (0..N), schrijft DPT 5.010.
     * - `byte`    : continue slider 0–255, DPT 5.010.
     * - `percent` : continue slider 0–100, DPT 5.001.
     * Standaard: `steps` als `steps` is ingesteld, anders `percent`.
     */
    speedMode?: "steps" | "byte" | "percent";
    /** Aantal discrete standen (2..10). Alleen bij `speedMode: "steps"`. */
    steps?: number;
    /** Optionele naamlabels per stand, bijv. ["Laag","Middel","Hoog"]. */
    stepLabels?: string[];
  };
  oscillate?: { ga: GA; statusGa?: GA };
  direction?: { ga: GA; statusGa?: GA };
}

export interface FanDevice extends DeviceBase {
  type: "fan";
  fan: FanConfig;
}

/* --------------------------------------------------------------------- */
/*  Universal — customer-configurable multi-button panel                 */
/* --------------------------------------------------------------------- */

/** A single telegram that a universal-button writes. */
export type UniversalRole =
  | "bit"
  | "byte"
  | "percent"
  | "temperature"
  | "raw_int";

export interface UniversalAction {
  ga: GA;
  role: UniversalRole;
  /** Numeric for byte/percent/temperature, boolean for bit. */
  value: number | boolean;
}

export interface UniversalButton {
  id: string;
  label: string;
  icon?: string;
  /** Main tap action. */
  action: UniversalAction;
  /** Optional second tap action — useful for toggles where tapping
   *  again should send a different value. If set, tapping toggles
   *  between `action` and `actionOff` based on `statusGa`. */
  actionOff?: UniversalAction;
  /** If set, the UI reads this GA to decide whether the button is "on". */
  statusGa?: GA;
  /** The value in `statusGa` that means "on". Defaults to `true`/1. */
  statusOnValue?: number | boolean;
  /** Visual emphasis. */
  style?: "primary" | "neutral" | "brass" | "danger";
  /**
   * Optional per-button confirmation prompt.
   * - `true`                → default "Weet je zeker?" dialog.
   * - `{ pin: "1234" }`    → 4-digit PIN entry.
   * - `{ message: "..." }` → custom text.
   */
  confirm?: ConfirmPrompt;
}

export interface UniversalConfig {
  columns?: number; // default 2
  /** Icon name shown in the group chip and tile header (e.g. "bolt", "home"). */
  icon?: string;
  buttons: UniversalButton[];
}

export interface UniversalDevice extends DeviceBase {
  type: "universal";
  universal: UniversalConfig;
}

/* --------------------------------------------------------------------- */
/*  WTW — Warmte-Terugwin / HRV ventilatie                               */
/* --------------------------------------------------------------------- */

/** KNX data point types supported by the WTW device for buttons and status. */
export type WtwDpt =
  // ── 1-bit ───────────────────────────────────────────────────────────────
  | "1.001"   // boolean: aan/uit, actief/inactief
  | "1.002"   // boolean: true/false
  | "1.008"   // up/down
  | "1.009"   // open/close
  | "1.011"   // active/inactive
  // ── 1-byte signed ───────────────────────────────────────────────────────
  | "6.001"   // DPT6.001 signed byte −128..127
  // ── 1-byte unsigned ─────────────────────────────────────────────────────
  | "5.001"   // percentage 0–100 %
  | "5.010"   // unsigned byte 0–255 (stand, teller)
  // ── 2-byte unsigned ─────────────────────────────────────────────────────
  | "7.001"   // unsigned int 0–65535 (dagenteller e.d.)
  // ── 2-byte signed ───────────────────────────────────────────────────────
  | "8.001"   // signed 2-byte (flow rate e.d.)
  // ── 2-byte float ────────────────────────────────────────────────────────
  | "9.001"   // temperatuur (°C)
  | "9.002"   // temperatuurverschil (K)
  | "9.004"   // verlichtingssterkte (lux)
  | "9.005"   // windsnelheid (m/s)
  | "9.006"   // luchtdruk (Pa)
  | "9.007"   // relatieve vochtigheid (%RH)
  | "9.008"   // luchtkwaliteit / CO₂ (ppm)
  | "9.009"   // volumestroom (m³/h)
  | "9.020"   // spanning (mV)
  | "9.021"   // stroom (mA)
  // ── 4-byte unsigned ─────────────────────────────────────────────────────
  | "12.001"  // unsigned 32-bit (0–4 294 967 295)
  // ── 4-byte signed ───────────────────────────────────────────────────────
  | "13.001"  // signed 32-bit
  // ── 4-byte float ────────────────────────────────────────────────────────
  | "14.019"  // elektrisch vermogen (W)
  | "14.068"  // windsnelheid (m/s) IEEE754
  // ── Speciaal ────────────────────────────────────────────────────────────
  | "hex";    // Allen voor status: waarde als hex-string weergeven

export interface WtwButton {
  id: string;
  label: string;
  /** KNX groepsadres om naartoe te schrijven. */
  ga: string;
  /** DPT bepaalt het telegram-type. Hex is niet geldig voor knoppen. */
  dpt: Exclude<WtwDpt, "hex">;
  /** Waarde om te versturen. Boolean voor 1.001, getal voor de rest. */
  value: number | boolean;
  /** Optioneel terugkoppeling-GA (bepaalt of de knop "actief" is). */
  statusGa?: string;
  /** Welke waarde in statusGa de "actief"-toestand aangeeft (standaard true/1). */
  statusOnValue?: number | boolean;
}

export interface WtwStatusItem {
  id: string;
  label: string;
  /** KNX groepsadres om te lezen. */
  ga: string;
  /** DPT bepaalt de weergave-opmaak. */
  dpt: WtwDpt;
  /** Optioneel eenheids-achtervoegsel, bijv. "dagen" of "°C". */
  unit?: string;
  /**
   * Icoon-naam (uit de centrale icon-library) die altijd links naast het label
   * wordt getoond. Optioneel — als `icon0`/`icon1` ook zijn ingesteld, worden
   * die gebruikt als de waarde bekend is.
   */
  icon?: string;
  /**
   * Icoon-naam voor waarde 0 / false / "OK" (bijv. check, fan_off, lock).
   * Vervangt de tekst-badge als ingesteld.
   */
  icon0?: string;
  /**
   * Icoon-naam voor waarde 1 / true / "Actief" (bijv. warning, filter_full).
   * Vervangt de tekst-badge als ingesteld.
   */
  icon1?: string;
}

export interface WtwConfig {
  buttons?: WtwButton[];
  status?: WtwStatusItem[];
}

export interface WtwDevice extends DeviceBase {
  type: "wtw";
  wtw: WtwConfig;
}

/* --------------------------------------------------------------------- */
/*  Meldingen — KNX alarm/notification monitor                           */
/* --------------------------------------------------------------------- */

/** Urgency level of a single alert item. */
export type MeldingUrgency =
  | "urgent"           // Storing / kritiek — rood
  | "belangrijk"       // Waarschuwing — oranje
  | "minder_belangrijk"; // Informatie — goud/geel

export interface MeldingItem {
  id: string;
  /** Door de installateur opgegeven onderwerp, bijv. "Filter vuil". */
  label: string;
  /** KNX groepsadres (leesadres). */
  ga: string;
  /** DPT bepaalt de weergave en actief-detectie. */
  dpt: WtwDpt;
  urgency: MeldingUrgency;
  /**
   * Welke waarde betekent "melding actief"?
   * Default: 1 / true voor 1-bit DPTs, elke waarde ≠ 0 voor de rest.
   */
  activeValue?: number | boolean;
  /** Optioneel icoon uit de icon-library. */
  icon?: string;
  /** Optioneel: custom tekst als de melding actief is. */
  activeLabel?: string;
  /** Optioneel: custom tekst als de melding inactief is. */
  inactiveLabel?: string;
}

export interface MeldingConfig {
  items: MeldingItem[];
}

export interface MeldingDevice extends DeviceBase {
  type: "melding";
  melding: MeldingConfig;
}

/* --------------------------------------------------------------------- */
/*  Lutron Homeworks — telnet integratie + knop → KNX mappings            */
/* --------------------------------------------------------------------- */

export interface LutronTelnetConfig {
  /** Wanneer true en `host` gezet: backend maakt telnet-verbinding + monitoring. */
  enabled?: boolean;
  /** Hostname of IP van de processor (of `bridgeHost` als fallback). */
  host?: string;
  /** Standaard 23. */
  port?: number;
  /** Leeg = geen login-prompt handling. */
  username?: string;
  /** Alleen server-side in house.json; wordt uit config voor clients gestript. */
  password?: string;
  /**
   * Commando’s direct na login (zonder \\r\\n in JSON).
   * Standaard: `["#MONITORING,3,1"]` (button monitoring aan).
   */
  postLoginCommands?: string[];
}

/** Eén KNX-schrijfactie vanuit een Lutron-mapping. */
export interface LutronKnxBinding {
  ga: GA;
  role: string;
  value: number | boolean | number[] | Rgb232Triplet;
  /** Alleen bij `switch` / `bit`: pulsduur ms (true → false). */
  pulseMs?: number;
}

/** Lutron `~DEVICE,integration,component,action` → KNX. */
export interface LutronButtonToKnxMapping {
  id: string;
  label: string;
  integrationId: number;
  componentNumber: number;
  /** Bijv. 3 = press, 4 = release. Weglaten = elke actie op dit component. */
  actionNumber?: number;
  knx: LutronKnxBinding;
}

/** Centrale Lutron Homeworks-koppeling (technische configuratie, zoals `knx`). */
export interface HouseLutronConfig {
  /** Legacy: gebruikt als `telnet.host` ontbreekt. */
  bridgeHost?: string;
  telnet?: LutronTelnetConfig;
  /** Keypad `~DEVICE` → KNX (optioneel). */
  buttonToKnx?: LutronButtonToKnxMapping[];
}

export interface LutronHomeworksConfig {
  /** Legacy: gebruikt als `telnet.host` ontbreekt. */
  bridgeHost?: string;
  zoneAddress?: string;
  telnet?: LutronTelnetConfig;
  buttonToKnx?: LutronButtonToKnxMapping[];
}

export interface LutronHomeworksDevice extends DeviceBase {
  type: "lutron_homeworks";
  lutronHomeworks: LutronHomeworksConfig;
}

export type Device =
  | LightSwitchDevice
  | LightDimmerDevice
  | RgbwWwDevice
  | ShadingDevice
  | PositionActuatorDevice
  | ClimateDevice
  | SonosDevice
  | BluesoundDevice
  | CameraDevice
  | IntercomDevice
  | FireplaceDevice
  | AcDevice
  | FanDevice
  | UniversalDevice
  | WtwDevice
  | MeldingDevice
  | LutronHomeworksDevice;

/* --------------------------------------------------------------------- */
/*  Scenes                                                               */
/* --------------------------------------------------------------------- */

/** One KNX write that happens when a scene is triggered. */
export interface SceneAction {
  ga: GA;
  /** Role drives DPT selection (see `ROLE_DPT` + scene role mapping). */
  role:
    | "switch"
    | "dim_value"
    | "setpoint"
    | "position"
    | "scene_number"
    | "bit"
    | "byte"
    | "percent"
    | "temperature"
    /** Raw octets on one GA (`KnxBus.writeRaw`). */
    | "raw_bytes"
    /** DPT 232.600 — `value` is `[r,g,b]` or `Rgb232Triplet`. */
    | "rgb232"
    /** DPT1 puls (aan → wacht → uit), o.a. discrete haard-contacten. */
    | "pulse";
  value: number | boolean | number[] | Rgb232Triplet;
  /** Optioneel voor `role: "pulse"` (default 250 ms). */
  pulseMs?: number;
  /** Optional delay before this specific action fires (ms). Useful to
   *  stagger telegrams so the gateway isn't hammered. */
  delayMs?: number;
}

/** Media player command stored on a scene (Sonos / Bluesound). */
export type SceneMediaAction =
  | {
      deviceId: string;
      kind: "transport";
      action: "play" | "pause" | "stop" | "next" | "previous";
      delayMs?: number;
    }
  | {
      deviceId: string;
      kind: "volume";
      value: number;
      delayMs?: number;
    }
  | {
      deviceId: string;
      kind: "mute";
      muted: boolean;
      delayMs?: number;
    }
  | {
      deviceId: string;
      kind: "preset";
      presetId: string;
      /** Display label only — not sent to the player. */
      presetName?: string;
      uri?: string;
      delayMs?: number;
    };

export interface Scene {
  id: string;
  name: string;
  icon?: string;
  /** Optional accent colour, used purely for UI rendering. Hex string,
   *  e.g. "#B08A4E". */
  color?: string;
  actions: SceneAction[];
  /** Optional Sonos/Bluesound commands executed after/between KNX actions. */
  mediaActions?: SceneMediaAction[];
}

export interface Room {
  id: string;
  name: string;
  icon?: string;
  cover?: string;
  devices: Device[];
  /** Per-room scenes (rendered as a strip at the top of the room). */
  scenes?: Scene[];
}

export interface Floor {
  id: string;
  name: string;
  order?: number;
  icon?: string;
  rooms: Room[];
}

export interface GatewayConfig {
  host: string;
  port?: number;
  mode?: "tunneling" | "routing";
}

export interface User {
  id: string;
  username: string;
  displayName?: string;
  role: "admin" | "user";
  passwordHash: string;
  access?: {
    floors?: "*" | string[];
    rooms?: "*" | string[];
    canRelease?: "*" | string[];
    talkIntercoms?: "*" | string[];
    /** If false, the user can run scenes but cannot create/edit/delete them.
     *  Defaults to `true` — customers shouldn't need admin to tweak moods. */
    editScenes?: boolean;
  };
}

export interface HouseConfig {
  project: {
    id: string;
    name: string;
    timezone?: string;
    location?: { lat: number; lon: number };
  };
  /**
   * KNX-integratie. Stel `enabled: false` in om de KNX-bus volledig uit te
   * schakelen; de app start dan zonder verbindingspogingen.
   * Het hele blok mag ontbreken (zelfde effect als `enabled: false`).
   */
  knx?: {
    enabled?: boolean;
    gateway: GatewayConfig;
    physicalAddress?: string;
  };
  /** Lutron Homeworks telnet + optionele knop→KNX mappings. */
  lutron?: HouseLutronConfig;
  floors: Floor[];
  /**
   * KNX / Lutron devices that are NOT placed in a specific room.
   * They appear in the Systemen dashboard chips and can be added to favourites,
   * but are never shown in the room navigator.
   */
  devices?: Device[];
  /** Surveillance cameras (not tied to a room). */
  cameras?: CameraDevice[];
  /** Deurbel / intercom (not tied to a room). */
  intercoms?: IntercomDevice[];
  users?: User[];
  /** Global (house-wide) scenes — rendered on the dashboard. */
  scenes?: Scene[];
  /** Time / astro schedules — run by the backend scheduler. */
  schedules?: Schedule[];
  /** Installer-defined custom logs of arbitrary group addresses (graphs). */
  logs?: LogDef[];
  /** Satel alarm integration configuration. */
  satel?: {
    enabled?: boolean;
    partitions?: Array<{ number: number; name: string }>;
  };
  /** Wandtablet idle timeout + screensaver (Android client). */
  displayPanel?: {
    enabled?: boolean;
    idleHomeMinutes?: number;
    /** 0 = screensaver uit. */
    screensaverMinutes?: number;
    panelRoomId?: string;
    panelRoomName?: string;
    suppressScreensaverWhenMusicPlaying?: boolean;
    temperatureGa?: string;
    temperatureRoomId?: string;
    temperatureRoomName?: string;
  };
}

/* --------------------------------------------------------------------- */
/*  Logging — server-side time-series of group-address values            */
/* --------------------------------------------------------------------- */

export interface LogEntry {
  /** Group address to record. */
  ga: GA;
  /** Display name for this series in the graph legend. */
  label: string;
  /** Optional unit shown on the axis/legend (e.g. "°C", "%", "W"). */
  unit?: string;
}

export interface LogDef {
  id: string;
  name: string;
  entries: LogEntry[];
}

/* --------------------------------------------------------------------- */
/*  Schedules — time or astro triggers that run scenes / device lists    */
/* --------------------------------------------------------------------- */

/** Days-of-week bitmask using ISO weekday ordering.
 *  Index 0 = Monday … 6 = Sunday. */
export type WeekdayMask = [
  boolean, boolean, boolean, boolean, boolean, boolean, boolean
];

/** A guard that prevents a trigger from firing outside the given window.
 *  Can be a fixed "HH:MM" clock time, or another astro anchor (with its
 *  own offset) so users can say "at sunset, but not before sunrise+60m". */
export type ScheduleGuard =
  | { kind: "time"; time: string } // HH:MM, 24h local
  | {
      kind: "astro";
      event: "sunrise" | "sunset";
      offsetMin?: number; // signed minutes; default 0
    };

export type ScheduleTrigger =
  | {
      kind: "time";
      /** "HH:MM" in the project's local time zone. */
      time: string;
      days: WeekdayMask;
    }
  | {
      kind: "astro";
      event: "sunrise" | "sunset";
      /** Signed minutes relative to the solar event (negative = before). */
      offsetMin?: number;
      days: WeekdayMask;
      /** Optional lower bound – never fire earlier than this. */
      notBefore?: ScheduleGuard;
      /** Optional upper bound – never fire later than this. */
      notAfter?: ScheduleGuard;
    };

export type ScheduleAction =
  | { kind: "scene"; sceneId: string }
  | { kind: "actions"; actions: SceneAction[] };

export interface Schedule {
  id: string;
  name: string;
  /** If false the entry is kept but the scheduler skips it. */
  enabled: boolean;
  trigger: ScheduleTrigger;
  action: ScheduleAction;
  /** Populated by the scheduler after every fire; purely informational. */
  lastRun?: string; // ISO timestamp
}

export interface GAState {
  ga: GA;
  value: number | boolean | string | Rgb232Triplet;
  ts: number;
  dpt?: string;
}
