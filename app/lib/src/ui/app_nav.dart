import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// On Flutter web (esp. iPhone Safari), [GoRouter.push] adds browser history
/// entries. The edge swipe then flips between those pages — unwanted.
/// Flat [go] navigation keeps one history slot; swipe-back leaves the site.
bool get _flatWebNav => kIsWeb;

void appOpen(BuildContext context, String location) {
  if (_flatWebNav) {
    context.go(location);
  } else {
    context.push(location);
  }
}

void appBack(BuildContext context, {String fallback = '/'}) {
  if (_flatWebNav) {
    context.go(fallback);
    return;
  }
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
