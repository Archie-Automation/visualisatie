import {
  captureSnapshotFfmpeg,
  resolveFfmpegBin
} from "./cameraSnapshot";
import {
  detectCameraSourceProfile,
  profileLabel,
  resolveCameraLiveOptions,
  type CameraSourceProfile
} from "./cameraSource";
import type { CameraConfig } from "./types";

export interface CameraProbeResult {
  ok: boolean;
  role: "live" | "preview";
  latencyMs: number;
  jpegBytes: number;
  width: number | null;
  height: number | null;
  profile: CameraSourceProfile;
  profileLabel: string;
  warnings: string[];
  error: string | null;
}

export interface CameraProbeSummary {
  live: CameraProbeResult;
  preview: CameraProbeResult | null;
  recommended: {
    go2rtcFfmpeg: boolean;
    go2rtcVideoOnly: boolean;
    codec: "h264" | "h265" | null;
  };
  ffmpegAvailable: boolean;
}

function jpegDimensions(buf: Buffer): { width: number; height: number } | null {
  if (buf.length < 12 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
  let i = 2;
  while (i + 8 < buf.length) {
    if (buf[i] !== 0xff) {
      i++;
      continue;
    }
    const marker = buf[i + 1]!;
    if (marker === 0xc0 || marker === 0xc2) {
      return {
        height: buf.readUInt16BE(i + 5),
        width: buf.readUInt16BE(i + 7)
      };
    }
    const segLen = buf.readUInt16BE(i + 2);
    if (segLen < 2) break;
    i += 2 + segLen;
  }
  return null;
}

async function probeOneRtsp(
  rtsp: string,
  role: "live" | "preview",
  scaleWidth: number
): Promise<CameraProbeResult> {
  const profile = detectCameraSourceProfile(rtsp);
  const warnings: string[] = [];
  const start = Date.now();

  if (!resolveFfmpegBin()) {
    return {
      ok: false,
      role,
      latencyMs: 0,
      jpegBytes: 0,
      width: null,
      height: null,
      profile,
      profileLabel: profileLabel(profile),
      warnings: ["ffmpeg niet gevonden op de server"],
      error: "ffmpeg unavailable"
    };
  }

  try {
    const buf = await captureSnapshotFfmpeg(rtsp, {
      width: scaleWidth,
      timeoutMs: 15_000
    });
    const latencyMs = Date.now() - start;
    if (!buf || buf.length === 0) {
      return {
        ok: false,
        role,
        latencyMs,
        jpegBytes: 0,
        width: null,
        height: null,
        profile,
        profileLabel: profileLabel(profile),
        warnings,
        error: "geen frame ontvangen"
      };
    }
    const dims = jpegDimensions(buf);
    if (latencyMs > 8_000) {
      warnings.push("Trage RTSP-verbinding (>8s) — overweeg preview/substream");
    }
    if (dims && dims.width >= 1920) {
      warnings.push("Hoge resolutie — live kan zwaar zijn op tablets");
    }
    return {
      ok: true,
      role,
      latencyMs,
      jpegBytes: buf.length,
      width: dims?.width ?? null,
      height: dims?.height ?? null,
      profile,
      profileLabel: profileLabel(profile),
      warnings,
      error: null
    };
  } catch (err) {
    return {
      ok: false,
      role,
      latencyMs: Date.now() - start,
      jpegBytes: 0,
      width: null,
      height: null,
      profile,
      profileLabel: profileLabel(profile),
      warnings,
      error: err instanceof Error ? err.message : "probe failed"
    };
  }
}

export async function probeCameraStreams(body: {
  rtsp?: string;
  previewRtsp?: string;
  codec?: string;
}): Promise<CameraProbeSummary> {
  const rtsp = body.rtsp?.trim() ?? "";
  const previewRtsp = body.previewRtsp?.trim() ?? "";

  const live = rtsp
    ? await probeOneRtsp(rtsp, "live", 960)
    : {
        ok: false,
        role: "live" as const,
        latencyMs: 0,
        jpegBytes: 0,
        width: null,
        height: null,
        profile: "direct_camera" as const,
        profileLabel: profileLabel("direct_camera"),
        warnings: [],
        error: "rtsp URL ontbreekt"
      };

  const preview = previewRtsp
    ? await probeOneRtsp(previewRtsp, "preview", 640)
    : null;

  const cam: CameraConfig = {
    rtsp,
    previewRtsp: previewRtsp || undefined,
    codec: body.codec === "h265" ? "h265" : body.codec === "h264" ? "h264" : undefined
  };
  const opts = resolveCameraLiveOptions(cam, rtsp);

  return {
    live,
    preview,
    recommended: {
      go2rtcFfmpeg: opts.useFfmpeg,
      go2rtcVideoOnly: opts.videoOnly,
      codec: cam.codec ?? null
    },
    ffmpegAvailable: !!resolveFfmpegBin()
  };
}
