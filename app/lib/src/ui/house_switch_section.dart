import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../saved_houses.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';

/// Wissel van NUC. Elke woning houdt zijn eigen sessie.
class HouseSwitchSection extends ConsumerStatefulWidget {
  const HouseSwitchSection({super.key});

  @override
  ConsumerState<HouseSwitchSection> createState() => _HouseSwitchSectionState();
}

class _HouseSwitchSectionState extends ConsumerState<HouseSwitchSection> {
  List<SavedHouse> _houses = const [];
  Map<String, String> _users = const {};
  String? _active;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    savedHousesEpoch.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    savedHousesEpoch.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final houses = await HouseStore.list();
    final users = await HouseStore.sessionUsernames();
    final active = await HouseStore.activeKey();
    if (!mounted) return;
    setState(() {
      _houses = houses;
      _users = users;
      _active = active;
    });
  }

  Future<void> _open(SavedHouse house) async {
    if (_busyKey != null || house.key == _active) return;
    final router = GoRouter.of(context);
    setState(() => _busyKey = house.key);
    final ok = await openSavedHouse(house, ref.read(authProvider.notifier));
    if (ok) {
      router.go('/');
      return;
    }
    router.go('/login');
  }

  Future<void> _add() async {
    if (_busyKey != null) return;
    final router = GoRouter.of(context);
    setState(() => _busyKey = '_add');
    await parkActiveHouse();
    await ref.read(authProvider.notifier).clearLocal();
    router.go('/login?add=1');
  }

  Future<void> _remove(SavedHouse house) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Woning verwijderen'),
        content: Text(
          '${house.label} verdwijnt van deze telefoon. '
          'Het huis zelf blijft op de server staan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final router = GoRouter.of(context);
    final wasActive = house.key == _active;
    await HouseStore.remove(house.key);
    if (wasActive) {
      await ref.read(authProvider.notifier).logout();
      router.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_houses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nog geen woning op deze telefoon.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _addButton(),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _houses.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 50, color: LuxeColors.lineSoft),
                  _row(_houses[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _addButton(),
        ],
      ),
    );
  }

  Widget _addButton() {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: LuxeColors.ink,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: LuxeColors.line),
        shape: const StadiumBorder(),
      ),
      onPressed: _busyKey != null ? null : _add,
      child: const Text('Woning toevoegen'),
    );
  }

  Widget _row(SavedHouse house) {
    final active = house.key == _active;
    final user = _users[house.key];
    final busy = _busyKey == house.key;
    return InkWell(
      onTap: active || _busyKey != null ? null : () => _open(house),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_rounded : Icons.home_outlined,
              size: 20,
              color: LuxeColors.ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(house.label,
                      style: Theme.of(context).textTheme.bodyLarge),
                  Text(
                    active
                        ? 'Deze woning'
                        : (user != null && user.isNotEmpty
                            ? 'Ingelogd als $user'
                            : 'Inloggen nodig'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'Verwijderen',
                onPressed: _busyKey != null ? null : () => _remove(house),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: LuxeColors.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}
