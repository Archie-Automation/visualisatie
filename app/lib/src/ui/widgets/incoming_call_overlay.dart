import 'package:flutter/material.dart';

/// Previously a second accept-banner. Ringing now opens [IntercomScreen]
/// directly; this widget only keeps the tree shape.
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
