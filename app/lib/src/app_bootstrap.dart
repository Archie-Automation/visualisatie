import 'package:flutter/foundation.dart';

/// Verhoogt om de hele app opnieuw te mounten (nieuwe [ProviderScope], schone Riverpod-state).
final ValueNotifier<int> appBootEpoch = ValueNotifier<int>(0);
