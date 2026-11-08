import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'demo/demo_session.dart';
import 'pairing_api.dart';

/// iPhone-web op het thuisadres: eerst lokaal ingelogd, daarna het cloudadres
/// openen met dezelfde sessie. `?local=1` blijft thuis. Mislukt het, dan blijft
/// de lokale login staan.
Future<bool> handoffWebToRemote(String? token) async {
  if (!kReleaseMode) return false;
  if (token == null || token.isEmpty || isDemoToken(token)) return false;
  if (Uri.base.queryParameters['local'] == '1') return false;
  final ua = html.window.navigator.userAgent;
  if (!RegExp('iPhone|iPod', caseSensitive: false).hasMatch(ua)) return false;
  if (!_lanHost(Uri.base.host)) return false;
  try {
    final health = await http
        .get(Uri.parse('$apiBase/api/health'))
        .timeout(const Duration(seconds: 3));
    if (health.statusCode != 200) return false;
    final decoded = jsonDecode(health.body);
    if (decoded is! Map) return false;
    final remote = (decoded['remoteUrl'] as String?)?.trim();
    if (remote == null || remote.isEmpty) return false;
    final target = Uri.parse(remote);
    if (target.host.toLowerCase() == Uri.base.host.toLowerCase()) return false;
    final pair = await startPairing(token: token, transfer: true);
    if (!pair.qr.startsWith(target.origin)) return false;
    html.window.location.replace(pair.qr);
    return true;
  } catch (_) {
    return false;
  }
}

bool _lanHost(String host) {
  final h = host.trim().toLowerCase();
  if (h == 'localhost') return true;
  if (RegExp(r'^192\.168\.\d{1,3}\.\d{1,3}$').hasMatch(h)) return true;
  if (RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}$').hasMatch(h)) {
    return true;
  }
  final ten = RegExp(r'^10\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(h);
  return ten != null && ten.group(1) != '80';
}
