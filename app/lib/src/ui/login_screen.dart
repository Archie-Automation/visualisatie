import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:archie_os/l10n/app_localizations.dart';

import '../api.dart';
import '../saved_houses.dart';
import '../server_route.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.addHouse = false});

  /// Adresvelden open, om een woning toe te voegen naast de opgeslagen lijst.
  final bool addHouse;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _server = TextEditingController(text: localApiBase);
  final _remote = TextEditingController(text: remoteApiBase ?? '');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;
  List<SavedHouse> _houses = const [];
  Map<String, String> _sessionUsers = const {};
  String? _selectedKey;
  bool _showAddress = true;
  bool _relogin = false;
  bool _appliedHouseList = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      savedHousesEpoch.addListener(_loadHouses);
      _loadHouses();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) savedHousesEpoch.removeListener(_loadHouses);
    _server.dispose();
    _remote.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadHouses() async {
    final houses = await HouseStore.list();
    final users = await HouseStore.sessionUsernames();
    final active = await HouseStore.activeKey();
    if (!mounted) return;
    setState(() {
      _houses = houses;
      _sessionUsers = users;
      if (_selectedKey == null || !houses.any((h) => h.key == _selectedKey)) {
        _selectedKey = houses.any((h) => h.key == active)
            ? active
            : (houses.isEmpty ? null : houses.first.key);
      }
      if (!_appliedHouseList) {
        _appliedHouseList = true;
        _showAddress = widget.addHouse || houses.isEmpty;
      } else if (houses.isEmpty) {
        _showAddress = true;
      }
    });
  }

  SavedHouse? get _selected {
    for (final h in _houses) {
      if (h.key == _selectedKey) return h;
    }
    return null;
  }

  bool get _canOpen {
    final key = _selectedKey;
    if (kIsWeb || _showAddress || _relogin || key == null) return false;
    return _sessionUsers.containsKey(key);
  }

  bool get _askPassword => !_canOpen;

  Future<void> _useHouse(SavedHouse house) async {
    await setApiBase(house.localUrl);
    await setRemoteApiBase(house.remoteUrl);
    if (house.serverId != null) await setKnownServerId(house.serverId);
    await HouseStore.setActive(house.key);
    await chooseServerRoute();
  }

  Future<void> _openSelected() async {
    final house = _selected;
    if (house == null) return;
    final router = GoRouter.of(context);
    setState(() {
      _busy = true;
      _err = null;
    });
    final ok = await openSavedHouse(house, ref.read(authProvider.notifier));
    if (ok) {
      router.go('/');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _relogin = true;
      _err = 'Sessie verlopen. Log opnieuw in.';
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _err = null;
    });

    if (!kIsWeb) {
      if (_showAddress && _server.text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _err = 'Vul het adres van de woning in.';
        });
        return;
      }
      await parkActiveHouse();
      final selected = _selected;
      if (selected != null && !_showAddress) {
        if (_relogin) {
          await _useHouse(selected);
          await ref.read(authProvider.notifier).logout();
        } else {
          await _useHouse(selected);
        }
      } else {
        await setApiBase(_server.text);
        await setRemoteApiBase(
          _remote.text.trim().isEmpty ? null : _remote.text,
        );
        await chooseServerRoute();
      }
    }

    bool ok = false;
    try {
      ok = await ref.read(authProvider.notifier).login(
            _user.text.trim(),
            _pass.text,
          );
    } on FormatException catch (_) {
      ok = false;
    } on TypeError catch (_) {
      ok = false;
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = e.message;
      });
      return;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('login error: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = l10n.loginErrorNetwork;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _err = l10n.loginErrorBadCredentials;
      }
    });
    if (ok && mounted) context.go('/');
  }

  Future<void> _demo() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    await ref.read(authProvider.notifier).enterDemo();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showServer = !kIsWeb;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
                  radius: 32,
                  shadows: LuxeShadows.lift,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('ARCHIE OS',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 14),
                        Text(l10n.loginWelcomeTitle,
                            style: Theme.of(context).textTheme.displayMedium),
                        const SizedBox(height: 10),
                        Text(
                          l10n.loginSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 40),
                        if (showServer) ...[
                          if (_houses.isNotEmpty && !_showAddress) ...[
                            _housePicker(),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _showAddress = true;
                                        _relogin = false;
                                        _err = null;
                                        _server.text = '';
                                        _remote.text = '';
                                      }),
                              child: Text('Woning toevoegen',
                                  style: TextStyle(color: LuxeColors.inkSoft)),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_showAddress) ...[
                            _field(
                              _server,
                              'Server (thuis)',
                              hint: 'http://192.168.1.20:4000',
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 14),
                            _field(
                              _remote,
                              'Adres buitenshuis (optioneel)',
                              hint: 'https://huis.archiecloud.nl',
                              keyboardType: TextInputType.url,
                            ),
                            if (_houses.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _showAddress = false;
                                          _err = null;
                                        }),
                                child: Text('Opgeslagen woningen',
                                    style: TextStyle(color: LuxeColors.inkSoft)),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                        ],
                        if (_askPassword) ...[
                          _field(_user, l10n.loginUserLabel),
                          const SizedBox(height: 22),
                          _field(_pass, l10n.loginPasswordLabel, obscure: true),
                          const SizedBox(height: 36),
                        ] else
                          const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: LuxeColors.ink,
                            foregroundColor: LuxeColors.onInk,
                            minimumSize: const Size.fromHeight(60),
                            shape: StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: _busy
                              ? null
                              : (_canOpen ? _openSelected : _submit),
                          child: _busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: LuxeColors.onInk),
                                )
                              : Text(
                                  _canOpen ? 'Openen' : l10n.loginAction,
                                  style: TextStyle(
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: LuxeColors.onInk,
                                  ),
                                ),
                        ),
                        if (_canOpen)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _relogin = true;
                                      _err = null;
                                    }),
                            child: Text('Ander account op deze woning',
                                style: TextStyle(color: LuxeColors.inkSoft)),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: LuxeColors.ink,
                            minimumSize: const Size.fromHeight(52),
                            side: BorderSide(color: LuxeColors.line),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _busy ? null : _demo,
                          child: const Text(
                            'Demo',
                            style: TextStyle(
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _busy ? null : () => context.go('/pair'),
                          child: Text('Ik heb een koppelcode',
                              style: TextStyle(color: LuxeColors.inkSoft)),
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 12),
                          Text(_err!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: LuxeColors.danger)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _housePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Woning',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: LuxeColors.inkSoft,
                )),
        const SizedBox(height: 8),
        for (final h in _houses) ...[
          _houseRow(h),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _houseRow(SavedHouse house) {
    final selected = house.key == _selectedKey;
    final user = _sessionUsers[house.key];
    return Material(
      color: selected
          ? LuxeColors.ink.withValues(alpha: 0.06)
          : LuxeColors.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy
            ? null
            : () => setState(() {
                  _selectedKey = house.key;
                  _relogin = false;
                  _err = null;
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.home_rounded : Icons.home_outlined,
                size: 20,
                color: LuxeColors.ink,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(house.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: LuxeColors.ink,
                        )),
                    Text(
                      user != null && user.isNotEmpty
                          ? 'Ingelogd als $user'
                          : houseHostLabel(house.localUrl),
                      style: TextStyle(fontSize: 12, color: LuxeColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 15, color: LuxeColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: LuxeColors.inkSoft),
        hintStyle: TextStyle(color: LuxeColors.inkSoft.withValues(alpha: 0.7)),
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.6),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: LuxeColors.ink, width: 1.4),
        ),
      ),
    );
  }
}
