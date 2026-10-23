import '../models.dart';
import 'demo_house.dart';

/// Buitenverlichting: aan bij zonsondergang, uit bij zonsopkomst.
List<Schedule> demoOutdoorSchedules() {
  final config = demoHouse.config;

  SceneAction switchTo(String id, bool on) {
    final device = config.deviceById(id);
    final ga = device?.ga['switch'];
    if (ga == null) {
      throw StateError('Geen schakeladres voor $id');
    }
    return SceneAction(ga: ga, role: SceneRole.switch_, value: on);
  }

  Schedule astro({
    required String id,
    required String name,
    required AstroEvent event,
    required bool on,
  }) {
    return Schedule(
      id: id,
      name: name,
      enabled: true,
      trigger: AstroTrigger(event: event, days: kAllDays),
      action: ScheduleActionsAction(
        actions: [
          switchTo('demo-light-gevel', on),
          switchTo('demo-light-tuin', on),
        ],
      ),
    );
  }

  return [
    astro(
      id: 'sch-buiten-aan',
      name: 'Buitenverlichting aan',
      event: AstroEvent.sunset,
      on: true,
    ),
    astro(
      id: 'sch-buiten-uit',
      name: 'Buitenverlichting uit',
      event: AstroEvent.sunrise,
      on: false,
    ),
  ];
}

Map<String, dynamic> demoSchedulePatches(String id) {
  for (final schedule in demoOutdoorSchedules()) {
    if (schedule.id != id) continue;
    final action = schedule.action;
    if (action is! ScheduleActionsAction) return const {};
    return {for (final step in action.actions) step.ga: step.value};
  }
  return const {};
}
