import 'app_bootstrap.dart';

Future<void> fullAppRemountOrReload() async {
  appBootEpoch.value = appBootEpoch.value + 1;
}
