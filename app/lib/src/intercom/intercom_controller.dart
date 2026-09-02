// Platform-specifieke SIP: native sip_ua, web JsSIP.
export 'intercom_controller_web.dart'
    if (dart.library.io) 'intercom_controller_io.dart';
