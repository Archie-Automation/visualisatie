import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// On Flutter web (esp. iPhone Safari), history [push] lets edge-swipe flip
/// between routes. Prefer [replace] so the URL updates without a back stack.
/// [from] is then the only record of where Back should go.
bool get _flatWebNav => kIsWeb;

void appOpen(BuildContext context, String location) {
  final dest = _withFrom(context, location);
  if (_flatWebNav) {
    context.replace(dest);
  } else {
    context.push(dest);
  }
}

void appBack(BuildContext context, {String fallback = '/'}) {
  final target = _readFrom(context) ?? fallback;
  if (_flatWebNav) {
    context.replace(target);
    return;
  }
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(target);
  }
}

/// Stamp the current path so Back can return there when there is no stack.
String _withFrom(BuildContext context, String location) {
  final dest = Uri.parse(location);
  if (dest.queryParameters.containsKey('from')) return location;
  var from = '/';
  try {
    final path = GoRouterState.of(context).uri.path;
    if (path.isNotEmpty) from = path;
  } catch (_) {
    /* not under GoRouter */
  }
  if (!_isInternalPath(from)) from = '/';
  return dest.replace(queryParameters: {
    ...dest.queryParameters,
    'from': from,
  }).toString();
}

String? _readFrom(BuildContext context) {
  try {
    final raw = GoRouterState.of(context).uri.queryParameters['from'];
    if (_isInternalPath(raw)) return raw;
  } catch (_) {
    /* not under GoRouter */
  }
  return null;
}

bool _isInternalPath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (!path.startsWith('/')) return false;
  if (path.startsWith('//')) return false;
  return true;
}
