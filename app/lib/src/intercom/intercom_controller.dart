/// Platform-specifieke SIP-intercom: native/desktop gebruikt sip_ua, web een no-op stub.
export 'intercom_controller_stub.dart'
    if (dart.library.io) 'intercom_controller_io.dart';
