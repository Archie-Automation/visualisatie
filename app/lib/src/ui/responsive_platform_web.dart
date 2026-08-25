import 'dart:html' as html;

/// True for phone browsers only. iPad / Android tablets must use size
/// breakpoints so they match the wall-panel layout.
bool get isPhoneWebUserAgent {
  final nav = html.window.navigator;
  final ua = nav.userAgent.toLowerCase();
  if (ua.contains('ipad') || ua.contains('tablet') || ua.contains('silk')) {
    return false;
  }
  // iPadOS 13+ often reports a Macintosh desktop UA.
  final platform = (nav.platform ?? '').toLowerCase();
  final touches = nav.maxTouchPoints ?? 0;
  if (platform.contains('mac') && touches > 1) return false;

  if (ua.contains('iphone') || ua.contains('ipod')) return true;
  // Android phones include "Mobile"; most tablets omit it.
  if (ua.contains('android') && ua.contains('mobile')) return true;
  return false;
}
