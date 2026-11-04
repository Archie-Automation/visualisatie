import 'package:archie_os/src/saved_houses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('zelfde serverId valt samen en houdt de naam', () async {
    final first = await HouseStore.upsert(
      localUrl: 'http://192.168.1.20:4000',
      name: 'Villa',
    );
    expect(first.key, 'url:http://192.168.1.20:4000');

    await HouseStore.saveSession(
      first.key,
      const HouseSession(token: 'tok-a', username: 'jan'),
    );

    final learned = await HouseStore.upsert(
      localUrl: 'http://192.168.1.20:4000',
      serverId: 'srv-1',
      name: '',
    );
    expect(learned.key, 'sid:srv-1');
    expect(learned.name, 'Villa');
    expect((await HouseStore.sessionFor('sid:srv-1'))!.token, 'tok-a');

    final merged = await HouseStore.upsert(
      localUrl: 'http://10.0.0.5:4000',
      remoteUrl: 'https://villa.archiecloud.nl',
      serverId: 'srv-1',
      name: '',
    );

    expect(merged.key, 'sid:srv-1');
    expect(merged.name, 'Villa');
    expect(merged.localUrl, 'http://10.0.0.5:4000');
    expect(merged.remoteUrl, 'https://villa.archiecloud.nl');

    final houses = await HouseStore.list();
    expect(houses, hasLength(1));
    expect(await HouseStore.sessionFor('sid:srv-1'), isNotNull);
    expect(await HouseStore.sessionFor(first.key), isNull);
    expect((await HouseStore.sessionFor('sid:srv-1'))!.token, 'tok-a');
  });

  test('sessies blijven per woning gescheiden', () async {
    final a = await HouseStore.upsert(
      localUrl: 'http://10.0.0.1:4000',
      serverId: 'a',
      name: 'Huis A',
    );
    final b = await HouseStore.upsert(
      localUrl: 'http://10.0.0.2:4000',
      serverId: 'b',
      name: 'Huis B',
    );
    await HouseStore.saveSession(
      a.key,
      const HouseSession(token: 'ta', username: 'ann'),
    );
    await HouseStore.saveSession(
      b.key,
      const HouseSession(token: 'tb', username: 'bob'),
    );

    expect((await HouseStore.sessionFor(a.key))!.token, 'ta');
    expect((await HouseStore.sessionFor(b.key))!.token, 'tb');

    await HouseStore.dropSession(a.key);
    expect(await HouseStore.sessionFor(a.key), isNull);
    expect((await HouseStore.sessionFor(b.key))!.username, 'bob');
    expect(await HouseStore.list(), hasLength(2));
  });

  test('verwijderen haalt alleen die woning en sessie weg', () async {
    final a = await HouseStore.upsert(
      localUrl: 'http://10.0.0.1:4000',
      serverId: 'a',
      name: 'Huis A',
    );
    await HouseStore.upsert(
      localUrl: 'http://10.0.0.2:4000',
      serverId: 'b',
      name: 'Huis B',
    );
    await HouseStore.setActive(a.key);
    await HouseStore.saveSession(
      a.key,
      const HouseSession(token: 'ta', username: 'ann'),
    );

    await HouseStore.remove(a.key);

    final left = await HouseStore.list();
    expect(left, hasLength(1));
    expect(left.single.serverId, 'b');
    expect(await HouseStore.activeKey(), isNull);
    expect(await HouseStore.sessionFor(a.key), isNull);
  });
}
