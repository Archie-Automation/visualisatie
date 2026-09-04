import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/server_update.dart';

ServerUpdateStatus _s(String state, {String message = ''}) => ServerUpdateStatus(
      state: state,
      message: message,
      agentReady: true,
    );

void main() {
  test('idle after running is success, not a 25-minute wait', () {
    expect(
      decideServerUpdateWait(
        status: _s('idle', message: 'Wacht op update-opdracht.'),
        sawBusy: true,
        sawOutage: false,
        elapsed: Duration.zero,
      ),
      ServerUpdateWaitDecision.success,
    );
  });

  test('idle after API outage is success', () {
    expect(
      decideServerUpdateWait(
        status: _s('idle', message: 'Wacht op update-opdracht.'),
        sawBusy: false,
        sawOutage: true,
        elapsed: Duration.zero,
      ),
      ServerUpdateWaitDecision.success,
    );
  });

  test('queued and running keep waiting', () {
    expect(
      decideServerUpdateWait(
        status: _s('running', message: 'Software bouwen.'),
        sawBusy: true,
        sawOutage: false,
        elapsed: const Duration(minutes: 5),
      ),
      ServerUpdateWaitDecision.wait,
    );
  });

  test('error is error', () {
    expect(
      decideServerUpdateWait(
        status: _s('error', message: 'mislukt'),
        sawBusy: true,
        sawOutage: false,
        elapsed: Duration.zero,
      ),
      ServerUpdateWaitDecision.error,
    );
  });

  test('progress hides the idle wait-for-command text', () {
    expect(
      serverUpdateProgressMessage(
        _s('idle', message: 'Wacht op update-opdracht.'),
      ),
      'Server is bijgewerkt.',
    );
  });
}
