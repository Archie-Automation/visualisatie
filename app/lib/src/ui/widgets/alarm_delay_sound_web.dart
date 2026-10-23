// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:js' as js;

import 'package:flutter/services.dart';

const _slowAsset = 'assets/sounds/alarm_delay_slow.mp3';
const _fastAsset = 'assets/sounds/alarm_delay_fast.mp3';

String? _slowUrl;
String? _fastUrl;
Future<void>? _loading;

Future<void> alarmDelayPrepare() {
  return _loading ??= _load();
}

Future<void> alarmDelaySlow() async {
  await alarmDelayPrepare();
  final url = _slowUrl;
  if (url == null) return;
  _play(url);
}

Future<void> alarmDelayFast() async {
  await alarmDelayPrepare();
  final url = _fastUrl;
  if (url == null) return;
  _play(url);
}

void alarmDelayStop() {
  js.context.callMethod('eval', [
    '''
(function(){
  var slot = window.__archieAlarm;
  if (!slot || !slot.a) return;
  try { slot.a.pause(); } catch (e) {}
  slot.a.src = '';
  slot.a = null;
})()
''',
  ]);
}

Future<void> _load() async {
  final slow = await rootBundle.load(_slowAsset);
  final fast = await rootBundle.load(_fastAsset);
  _slowUrl = _blobUrl(slow);
  _fastUrl = _blobUrl(fast);
}

String _blobUrl(ByteData data) {
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final b64 = base64Encode(bytes);
  final url = js.context.callMethod('eval', [
    '''
(function(){
  var bin = atob("$b64");
  var arr = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return URL.createObjectURL(new Blob([arr], {type: "audio/mpeg"}));
})()
''',
  ]);
  return url as String;
}

void _play(String url) {
  js.context.callMethod('eval', [
    '''
(function(){
  var slot = window.__archieAlarm = window.__archieAlarm || {};
  if (slot.a) {
    try { slot.a.pause(); } catch (e) {}
    slot.a.src = "";
  }
  var a = new Audio("$url");
  a.loop = true;
  a.volume = 1;
  slot.a = a;
  var p = a.play();
  if (p && p.catch) p.catch(function(){});
})()
''',
  ]);
}
