import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// On Flutter web (esp. iPhone Safari), history [push] lets edge-swipe flip
/// between routes. Prefer [replace] so the URL updates without a back stack.
bool get _flatWebNav => kIsWeb;

void appOpen(BuildContext context, String location) {
  if (_flatWebNav) {
    context.replace(location);
  } else {
    context.push(location);
  }
}

void appBack(BuildContext context, {String fallback = '/'}) {
  if (_flatWebNav) {
    context.replace(fallback);
    return;
  }
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
