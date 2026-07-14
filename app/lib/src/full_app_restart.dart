import 'full_app_restart_io.dart'
    if (dart.library.html) 'full_app_restart_web.dart' as plat;

/// Volledige client-“herstart”: web = pagina reload; overige platforms = nieuwe app-boom.
Future<void> fullAppRemountOrReload() => plat.fullAppRemountOrReload();
