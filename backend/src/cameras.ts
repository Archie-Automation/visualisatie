import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { walkDevices } from "./config";
import { intercomSupportsRelease } from "./intercomReleaseMode";
import { logger } from "./logger";
import type {
  CameraConfig,
  CameraDevice,
  HouseConfig,
  IntercomDevice
} from "./types";
import {
  detectCameraSourceProfile,
  resolveCameraLiveOptions
} from "./cameraSource";

export { detectCameraSourceProfile, resolveCameraLiveOptions, snapshotRtspForCamera, snapshotScaleWidth, profileLabel } from "./cameraSource";
export type { CameraSourceProfile, ResolvedCameraLiveOptions } from "./cameraSource";

/** View-only camera – never any talkback. */
export interface CameraPublic {
  id: string;
  name: string;
  kind: "camera";
  aspect: string;
  hls: string;
  webrtc: string;
  whep: string;
  snapshot: string;
}

/** Intercom – WebRTC always, talk-back always, optional door release. */
export interface IntercomPublic {
  id: string;
  name: string;
  kind: "intercom";
  aspect: string;
  webrtc: string;
  snapshot: string;
  canRelease: boolean;
}

function sanitiseId(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/-+/g, "-");
}

export function cameraPath(
  d: CameraDevice | IntercomDevice
): string {
  const cfg = d.type === "camera" ? d.camera : d.intercom;
  const raw = cfg.path?.trim();
  const id = d.id.trim();
  return sanitiseId(raw && raw.length > 0 ? raw : id);
}

/** Voor go2rtc `ffmpeg:`-bronnen: expliciet pad in yaml (Windows heeft zelden ffmpeg op PATH). */
function resolveFfmpegBinForGo2rtc(): string | null {
  // FFMPEG_PATH / GO2RTC_FFMPEG_BIN allow the operator to supply the exact
  // path that go2rtc should use. On Windows, paths with spaces must be given
  // as the 8.3 short form because go2rtc splits on the first space when it
  // invokes ffmpeg (e.g. FFMPEG_PATH=C:\Users\GEBRUI~1\KNXAPP~1\tools\ffmpeg.exe).
  const raw =
    process.env.FFMPEG_PATH?.trim() ||
    process.env.GO2RTC_FFMPEG_BIN?.trim();
  if (raw) {
    const abs = path.isAbsolute(raw) ? raw : path.resolve(process.cwd(), raw);
    if (fs.existsSync(abs)) return abs;
    logger.warn({ raw }, "FFMPEG_PATH gezet maar bestand bestaat niet");
  }
  const toolsGuess = path.resolve(
    process.cwd(),
    "..",
    "tools",
    process.platform === "win32" ? "ffmpeg.exe" : "ffmpeg"
  );
  if (fs.existsSync(toolsGuess)) return toolsGuess;
  const usrBin = "/usr/bin/ffmpeg";
  if (fs.existsSync(usrBin)) return usrBin;
  return null;
}

function yamlUsesFfmpegSources(yaml: string): boolean {
  return /\bffmpeg:[^\s#]+/.test(yaml);
}

export function collectCameras(cfg: HouseConfig): CameraDevice[] {
  return [...(cfg.cameras ?? [])];
}

export function collectIntercoms(cfg: HouseConfig): IntercomDevice[] {
  return [...(cfg.intercoms ?? [])];
}

export function publicCamera(
  cam: CameraDevice,
  mediaBase: string,
  apiBase: string
): CameraPublic {
  if (cam.camera.directHls) {
    return {
      id: cam.id,
      name: cam.name,
      kind: "camera",
      aspect: cam.camera.aspect ?? "16:9",
      hls: cam.camera.directHls,
      webrtc: "",
      whep: "",
      snapshot: `${apiBase}/api/cameras/${cam.id}/snapshot`
    };
  }
  const p = cameraPath(cam);
  // HLS is proxied through the backend so phones/tablets never need direct
  // access to go2rtc (:1984). WebRTC signalling already uses the same proxy.
  const hls = apiBase
    ? `${apiBase}/api/cameras/${cam.id}/hls.m3u8`
    : `${mediaBase}/api/stream.m3u8?src=${encodeURIComponent(p)}`;
  return {
    id: cam.id,
    name: cam.name,
    kind: "camera",
    aspect: cam.camera.aspect ?? "16:9",
    hls,
    webrtc: `${mediaBase}/api/webrtc?src=${encodeURIComponent(p)}`,
    whep: `${mediaBase}/api/whep?src=${encodeURIComponent(p)}`,
    snapshot: `${apiBase}/api/cameras/${cam.id}/snapshot`
  };
}

export function publicIntercom(
  ic: IntercomDevice,
  mediaBase: string,
  apiBase: string
): IntercomPublic {
  const p = cameraPath(ic);
  return {
    id: ic.id,
    name: ic.name,
    kind: "intercom",
    aspect: ic.intercom.aspect ?? "4:3",
    webrtc: `${mediaBase}/api/webrtc?src=${encodeURIComponent(p)}`,
    snapshot: `${apiBase}/api/intercoms/${ic.id}/snapshot`,
    canRelease: intercomSupportsRelease(ic)
  };
}

/**
 * Generate a go2rtc YAML configuration. Cameras are registered as plain
 * sources (view-only); intercoms always get `#backchannel=1` appended so
 * go2rtc negotiates the ONVIF two-way-audio channel.
 */
export function writeGo2rtcConfig(cfg: HouseConfig): string | null {
  const target = process.env.GO2RTC_CONFIG_PATH;
  if (!target) {
    logger.debug("GO2RTC_CONFIG_PATH not set – skipping go2rtc.yaml generation");
    return null;
  }

  const cams = collectCameras(cfg).filter((c) => c.camera.republish !== false);
  const ics = collectIntercoms(cfg);
  const ffmpegBin = resolveFfmpegBinForGo2rtc();
  const yaml = buildGo2rtcYaml(cams, ics, ffmpegBin);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, yaml, "utf-8");
  if (yamlUsesFfmpegSources(yaml) && !ffmpegBin) {
    logger.warn(
      "Streams gebruiken ffmpeg maar er is geen ffmpeg-binary gevonden. Zet FFMPEG_PATH of plaats tools/ffmpeg(.exe); anders faalt WebRTC/signalling."
    );
  }
  logger.info(
    { target, cameras: cams.length, intercoms: ics.length },
    "go2rtc config written"
  );
  return target;
}

function detectLanIPv4(): string | null {
  const nets = os.networkInterfaces();
  for (const ifaces of Object.values(nets)) {
    for (const net of ifaces ?? []) {
      if (net.family === "IPv4" && !net.internal) return net.address;
    }
  }
  return null;
}

/** ICE candidates so phones/tablets on the LAN can reach go2rtc WebRTC (UDP 8555). */
export function resolveWebRtcCandidates(): string[] {
  const out = new Set<string>(["stun:8555"]);

  const fromEnv = process.env.GO2RTC_WEBRTC_CANDIDATES?.trim();
  if (fromEnv) {
    for (const c of fromEnv.split(",")) {
      const t = c.trim();
      if (t) out.add(t);
    }
    return [...out];
  }

  for (const base of [
    process.env.MEDIA_BASE_URL,
    process.env.PUBLIC_API_BASE
  ]) {
    if (!base?.trim()) continue;
    try {
      const host = new URL(base.trim()).hostname;
      if (host && host !== "localhost" && host !== "127.0.0.1") {
        out.add(`${host}:8555`);
      }
    } catch {
      /* ignore */
    }
  }

  const lan = detectLanIPv4();
  if (lan) out.add(`${lan}:8555`);
  return [...out];
}

function buildGo2rtcYaml(
  cams: CameraDevice[],
  intercoms: IntercomDevice[],
  ffmpegBin: string | null
): string {
  const candidates = resolveWebRtcCandidates();
  const L: string[] = [
    "# Auto-generated by knx-backend. Do not edit by hand.",
    "log:",
    "  level: info",
    "",
    "api:",
    "  listen: :1984",
    "  origin: '*'",
    "",
    "rtsp:",
    "  listen: :8554",
    "",
    "webrtc:",
    "  listen: :8555",
    "  candidates:",
    ...candidates.map((c) => `    - ${yamlString(c)}`),
    "",
    "hls:",
    "  enable: yes",
    "  segment: 1",
    "  segment_count: 4",
    ""
  ];

  if (ffmpegBin) {
    L.push("ffmpeg:");
    L.push(`  bin: ${yamlString(ffmpegBin)}`);
    L.push("  timeout: 15");
    L.push(
      "  h264: \"-codec:v libx264 -g:v 15 -preset:v ultrafast -tune:v zerolatency -profile:v main -level:v 4.1\""
    );
    L.push("");
  }

  L.push("streams:");

  for (const cam of cams) {
    const p = cameraPath(cam);
    const cc = cam.camera;
    const sources = [
      decorateCameraRtspUrl(cc.rtsp, cc),
      ...(cc.sources ?? []).map((s) => decorateCameraRtspUrl(s, cc))
    ];
    pushStream(L, p, sources);
  }

  for (const ic of intercoms) {
    const p = cameraPath(ic);
    const tagged = /[#]backchannel=/i.test(ic.intercom.rtsp)
      ? ic.intercom.rtsp
      : `${ic.intercom.rtsp}#backchannel=1`;
    const sources = [tagged, ...(ic.intercom.sources ?? [])];
    pushStream(L, p, sources);
  }

  if (cams.length + intercoms.length === 0) L.push("  # (no cameras or intercoms configured)");
  return L.join("\n") + "\n";
}

function pushStream(lines: string[], p: string, sources: string[]) {
  const name = p.trim();
  if (!name) {
    logger.error("go2rtc streamnaam is leeg — dit zou niet mogen; check camera.path en id");
    return;
  }
  if (sources.length === 1) {
    lines.push(`  ${name}: ${yamlString(sources[0])}`);
  } else {
    lines.push(`  ${name}:`);
    for (const s of sources) lines.push(`    - ${yamlString(s)}`);
  }
}

function yamlString(s: string): string {
  if (/[:@#\s"'?&=]/.test(s))
    return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  return s;
}

function appendGo2rtcFragments(url: string, fragments: string[]): string {
  let u = url.trim();
  for (const frag of fragments) {
    const needle = `#${frag}`;
    if (u.includes(needle)) continue;
    u += needle;
  }
  return u;
}

/** go2rtc stream source: profile-aware native/ffmpeg wrapping. */
export function decorateCameraRtspUrl(raw: string, cam: CameraConfig): string {
  let u = raw.trim();
  if (/^ffmpeg:/i.test(u)) return u;
  if (!/^rtsps?:\/\//i.test(u)) return u;

  const opts = resolveCameraLiveOptions(cam, u);

  if (!opts.useFfmpeg) {
    const frags: string[] = [];
    if (opts.videoOnly) frags.push("media=video");
    if (detectCameraSourceProfile(u) === "synology_ss") frags.push("timeout=30");
    if (cam.go2rtcBackchannel0 === true) frags.push("backchannel=0");
    return appendGo2rtcFragments(u, frags);
  }

  u = `ffmpeg:${u}`;
  if (opts.transcodeH264 && !/#video=(copy|h264)\b/i.test(u)) {
    u += "#video=h264";
  } else if (!/#video=(copy|h264)\b/i.test(u)) {
    u += "#video=copy";
  }
  const frags: string[] = [];
  if (opts.videoOnly) frags.push("media=video");
  if (cam.go2rtcBackchannel0 === true) frags.push("backchannel=0");
  return appendGo2rtcFragments(u, frags);
}
