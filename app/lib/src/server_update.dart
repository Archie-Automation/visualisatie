import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

class ServerUpdateStatus {
  const ServerUpdateStatus({
    required this.state,
    required this.message,
    required this.agentReady,
    this.step,
    this.error,
  });

  final String state;
  final String message;
  final bool agentReady;
  final String? step;
  final String? error;

  bool get isBusy => state == 'queued' || state == 'running';
  bool get isSuccess => state == 'success';
  bool get isError => state == 'error';
  bool get isIdle => state == 'idle';

  factory ServerUpdateStatus.fromJson(Map<String, dynamic> j) {
    return ServerUpdateStatus(
      state: (j['state'] as String?)?.trim() ?? 'idle',
      message: (j['message'] as String?)?.trim() ?? '',
      agentReady: j['agentReady'] == true,
      step: (j['step'] as String?)?.trim(),
      error: (j['error'] as String?)?.trim(),
    );
  }
}

Future<ServerUpdateStatus> fetchServerUpdateStatus(String token) async {
  final res = await http
      .get(
        Uri.parse('$apiBase/api/admin/update'),
        headers: {'authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    throw StateError('Status ophalen mislukt (${res.statusCode})');
  }
  final body = jsonDecode(res.body);
  if (body is! Map<String, dynamic>) {
    throw StateError('Ongeldig antwoord');
  }
  return ServerUpdateStatus.fromJson(body);
}

Future<ServerUpdateStatus> postServerUpdate(String token) async {
  final res = await http
      .post(
        Uri.parse('$apiBase/api/admin/update'),
        headers: {'authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 12));
  final body = jsonDecode(res.body);
  if (body is! Map<String, dynamic>) {
    throw StateError('Ongeldig antwoord (${res.statusCode})');
  }
  if (res.statusCode != 200) {
    final msg = (body['message'] as String?)?.trim();
    throw StateError(
      msg != null && msg.isNotEmpty
          ? msg
          : 'Update geweigerd (${res.statusCode})',
    );
  }
  return ServerUpdateStatus.fromJson(body);
}

/// How the tablet should treat one poll while waiting for a NUC update.
enum ServerUpdateWaitDecision { wait, success, error }

/// The agent resets to idle ("Wacht op update-opdracht") immediately after
/// success. Missing that brief success used to leave the tablet waiting 25 min.
ServerUpdateWaitDecision decideServerUpdateWait({
  required ServerUpdateStatus status,
  required bool sawBusy,
  required bool sawOutage,
  required Duration elapsed,
}) {
  if (status.isError) return ServerUpdateWaitDecision.error;
  if (status.isSuccess) return ServerUpdateWaitDecision.success;
  if (status.isBusy) return ServerUpdateWaitDecision.wait;
  if (sawBusy || sawOutage) return ServerUpdateWaitDecision.success;
  if (elapsed >= const Duration(seconds: 15)) {
    return ServerUpdateWaitDecision.success;
  }
  return ServerUpdateWaitDecision.wait;
}

String serverUpdateProgressMessage(ServerUpdateStatus status) {
  final m = status.message.trim();
  if (status.isIdle &&
      (m.isEmpty || m.toLowerCase().contains('wacht op update'))) {
    return 'Server is bijgewerkt.';
  }
  if (m.isEmpty) return 'Bezig met bijwerken…';
  return m;
}

/// Poll until success/error. Survives the brief API outage at container swap.
Future<ServerUpdateStatus> waitForServerUpdate({
  required String token,
  void Function(String message)? onMessage,
  Duration timeout = const Duration(minutes: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  final started = DateTime.now();
  var last = const ServerUpdateStatus(
    state: 'queued',
    message: 'Update aangevraagd…',
    agentReady: true,
  );
  var sawBusy = false;
  var sawOutage = false;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await fetchServerUpdateStatus(token);
      if (last.isBusy) sawBusy = true;
      onMessage?.call(serverUpdateProgressMessage(last));
      switch (decideServerUpdateWait(
        status: last,
        sawBusy: sawBusy,
        sawOutage: sawOutage,
        elapsed: DateTime.now().difference(started),
      )) {
        case ServerUpdateWaitDecision.success:
          return ServerUpdateStatus(
            state: 'success',
            message: last.isSuccess
                ? (last.message.isEmpty
                    ? 'Server is bijgewerkt.'
                    : last.message)
                : 'Server is bijgewerkt.',
            agentReady: last.agentReady,
            step: last.step,
            error: last.error,
          );
        case ServerUpdateWaitDecision.error:
          return last;
        case ServerUpdateWaitDecision.wait:
          break;
      }
    } catch (_) {
      sawOutage = true;
      onMessage?.call('Server herstart. Even geduld…');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw StateError(
    'Update duurde langer dan ${timeout.inMinutes} minuten.',
  );
}
