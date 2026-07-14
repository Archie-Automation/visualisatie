import 'dart:html' as html;

/// True when the page runs in a phone/tablet browser (Flutter web / PWA).
bool get isMobileWebUserAgent {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipod') ||
      ua.contains('ipad') ||
      ua.contains('android') ||
      ua.contains('mobile');
}
