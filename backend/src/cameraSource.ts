import type { CameraConfig } from "./types";

export type CameraSourceProfile =
  | "synology_ss"
  | "nvr_recorder"
  | "direct_camera";

/** Detect RTSP source type from URL shape (no network I/O). */
export function detectCameraSourceProfile(rtsp: string): CameraSourceProfile {
  const u = rtsp.trim();
  if (/^rtsps?:\/\/syno:/i.test(u) && /\/Sms=\d+\.unicast/i.test(u)) {
    return "synology_ss";
  }
  if (
    /\/Streaming\/Channels\//i.test(u) ||
    /\/cam\/realmonitor/i.test(u) ||
    /\/Streaming\/tracks\//i.test(u) ||
    /\/h264Preview_\d+_(main|sub)_stream/i.test(u) ||
    /\/unicast\/c\d+\/s\d+\/live/i.test(u)
  ) {
    return "nvr_recorder";
  }
  return "direct_camera";
}

export interface ResolvedCameraLiveOptions {
  profile: CameraSourceProfile;
  videoOnly: boolean;
  useFfmpeg: boolean;
  transcodeH264: boolean;
}

/** Live go2rtc settings: explicit JSON flags override auto profile defaults. */
export function resolveCameraLiveOptions(
  cam: CameraConfig,
  rtsp: string
): ResolvedCameraLiveOptions {
  const profile = detectCameraSourceProfile(rtsp);
  const forceH264 = cam.codec === "h265";

  let useFfmpeg: boolean;
  if (forceH264) useFfmpeg = true;
  else if (cam.go2rtcFfmpeg === true) useFfmpeg = true;
  else if (cam.go2rtcFfmpeg === false) useFfmpeg = false;
  // Synology SS already serves H.264; native passthrough is faster and avoids
  // ffmpeg choking on high-res streams (e.g. 2560x1920 @ 30 fps on Sms=8).
  else useFfmpeg = profile === "nvr_recorder";

  let videoOnly: boolean;
  if (cam.go2rtcVideoOnly === true) videoOnly = true;
  else if (cam.go2rtcVideoOnly === false) videoOnly = false;
  else videoOnly = true;

  return {
    profile,
    videoOnly,
    useFfmpeg,
    transcodeH264: forceH264 || useFfmpeg
  };
}

/** RTSP URL used for JPEG thumbnails (preview/substream when configured). */
export function snapshotRtspForCamera(cam: CameraConfig): string | null {
  const url = (cam.previewRtsp?.trim() || cam.rtsp?.trim()) ?? "";
  if (!url || !/^rtsps?:\/\//i.test(url)) return null;
  return url;
}

/** Snapshot JPEG width: lower for dedicated preview streams. */
export function snapshotScaleWidth(cam: CameraConfig): number {
  if (cam.previewRtsp?.trim()) return 640;
  return 960;
}

export function profileLabel(profile: CameraSourceProfile): string {
  switch (profile) {
    case "synology_ss":
      return "Synology Surveillance Station";
    case "nvr_recorder":
      return "Recorder / NVR";
    default:
      return "Directe IP-camera";
  }
}
