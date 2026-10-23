import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/demo/demo_bus.dart';
import 'package:archie_os/src/demo/demo_effects.dart';
import 'package:archie_os/src/demo/demo_house.dart';
import 'package:archie_os/src/demo/demo_schedules.dart';
import 'package:archie_os/src/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('demowoning matches the prospect floor plan', () {
    final house = demoHouse.config;
    expect(
      house.floors.map((floor) => floor.name),
      ['Begane grond', 'Verdieping'],
    );
    expect(
      house.floors[0].rooms.map((room) => room.name),
      ['Entree', 'Woonkamer', 'Keuken', 'Bijkeuken', 'Toilet', 'Werkkamer'],
    );
    expect(
      house.floors[1].rooms.map((room) => room.name),
      ['Overloop', 'Slaapkamer 1', 'Slaapkamer 2', 'Slaapkamer 3', 'Badkamer'],
    );

    for (final floor in house.floors) {
      for (final room in floor.rooms) {
        expect(
          room.devices.where((device) => device.type == DeviceType.climate),
          hasLength(1),
          reason: room.name,
        );
      }
    }

    final living = house.floors[0].rooms[1];
    expect(
      living.devices.where((device) => device.type == DeviceType.fireplace),
      hasLength(1),
    );
    expect(
      living.devices.where((device) => device.type == DeviceType.shading),
      hasLength(2),
    );
    expect(house.projectName, 'Demo Archie');
    expect(
      house.allDevices.where((device) => device.type == DeviceType.ac).map((d) => d.id),
      ['demo-ac-woon', 'demo-ac-sl1', 'demo-ac-sl2', 'demo-ac-sl3'],
    );
    expect(
      house.allDevices.where((device) => device.name == 'Contacten' || device.name == 'Ramen'),
      isEmpty,
    );
    expect(
      house.allDevices.firstWhere((device) => device.type == DeviceType.wtw).name,
      'WTW',
    );
    final filter = house.allDevices
        .expand((device) => (device.raw['melding'] as Map?)?['items'] as List? ?? const [])
        .whereType<Map>()
        .where((item) => item['id'] == 'meld-filter')
        .single;
    expect(demoHouse.bus[filter['ga']], isFalse);
    final wtw = house.allDevices.firstWhere((device) => device.id == 'demo-wtw');
    final daysGa = ((wtw.raw['wtw'] as Map)['zehnder'] as Map)['filterDaysGa'];
    expect(demoHouse.bus[daysGa], 17);
    expect(
      house.scenes.firstWhere((scene) => scene.id == 'scn-weg').name,
      'Afwezig',
    );
    expect(house.cameras, hasLength(3));
    expect(house.intercoms, hasLength(1));
    expect(
      house.allDevices.where((device) => device.type == DeviceType.wtw),
      hasLength(1),
    );
    expect(
      house.allDevices.where((device) => device.type == DeviceType.mediaSonos),
      hasLength(5),
    );
    expect(
      house.scenes.map((scene) => scene.id),
      containsAll([
        'scn-welkom',
        'scn-film',
        'scn-koken',
        'scn-nacht',
        'scn-weg',
      ]),
    );
    expect(demoHouse.issuedGas, demoHouse.bus.length);
    expect(house.deviceById('demo-light-gevel')?.name, 'Gevel');
    expect(house.deviceById('demo-light-tuin')?.name, 'Tuinpad');
    final schedules = demoOutdoorSchedules();
    expect(
      schedules.map((schedule) => schedule.id),
      ['sch-buiten-aan', 'sch-buiten-uit'],
    );
    final on = schedules.first;
    expect((on.trigger as AstroTrigger).event, AstroEvent.sunset);
    expect((schedules.last.trigger as AstroTrigger).event, AstroEvent.sunrise);
    final patches = demoSchedulePatches('sch-buiten-aan');
    expect(patches[house.deviceById('demo-light-gevel')!.ga['switch']], isTrue);
    expect(patches[house.deviceById('demo-light-tuin')!.ga['switch']], isTrue);
    expect(
      demoSchedulePatches('sch-buiten-uit')[
          house.deviceById('demo-light-gevel')!.ga['switch']],
      isFalse,
    );
  });

  test('scenes point at real addresses and commands update status', () {
    final data = demoHouse;
    final owner = <String, String>{};
    for (final device in data.config.allDevices) {
      for (final ga in device.ga.values.toSet()) {
        expect(owner[ga], isNull, reason: '$ga on ${device.name} and ${owner[ga]}');
        owner[ga] = device.name;
      }
    }

    void expectKnown(Scene scene) {
      for (final action in scene.actions) {
        expect(
          data.bus.containsKey(action.ga),
          isTrue,
          reason: '${scene.name} ${action.ga}',
        );
      }
      for (final media in scene.mediaActions) {
        expect(data.mediaIds, contains(media.deviceId));
      }
    }

    for (final scene in data.config.scenes) {
      expectKnown(scene);
    }
    for (final floor in data.config.floors) {
      for (final room in floor.rooms) {
        for (final scene in room.scenes) {
          expectKnown(scene);
        }
      }
    }

    final light = data.config.floors[0].rooms[0].devices
        .firstWhere((device) => device.type == DeviceType.lightSwitch);
    final ga = light.ga['switch']!;
    expect(data.bus[ga], isTrue);
    final off = demoCommandPatches(data.config, data.bus, {
      'kind': 'light.switch',
      'deviceId': light.id,
      'on': false,
    });
    expect(off[ga], isFalse);

    final climate = data.config.allDevices
        .firstWhere((device) => device.id == 'demo-cl-woon');
    final setpoint = climate.ga['setpoint']!;
    final raised = demoCommandPatches(data.config, data.bus, {
      'kind': 'climate.setpoint',
      'deviceId': climate.id,
      'celsius': 23.0,
    });
    expect(raised[setpoint], 23.0);
    expect(raised[climate.ga['heat_demand']], isTrue);
  });

  test('opening a closed curtain steps the position down', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerDemoHooks();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(authProvider.notifier).enterDemo();
    final shade = demoHouse.config.deviceById('demo-sh-woon-g')!;
    final ga = shade.ga['position']!;
    for (var i = 0; i < 20 && !container.read(busProvider).values.containsKey(ga); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    container.read(busProvider.notifier).reflectAll({ga: 100});
    expect(container.read(busProvider).values[ga], 100);
    await container.read(busProvider.notifier).send({
      'kind': 'shading.move',
      'deviceId': shade.id,
      'direction': 'up',
    });
    expect(container.read(busProvider).values[ga], 90);
  });
}
