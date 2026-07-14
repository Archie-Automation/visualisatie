import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart' show apiBase;

/// Installer uses its own prefs keys so it does not clash with the customer app.
class InstallerAuthState {
  final String? token;
  final String? username;
  const InstallerAuthState({this.token, this.username});

  bool get isAuthed => token != null;
}

class InstallerAuthController extends Notifier<InstallerAuthState> {
  static const _kToken = 'luxe_installer_token';
  static const _kUser = 'luxe_installer_username';

  @override
  InstallerAuthState build() {
    Future.microtask(_restore);
    return const InstallerAuthState();
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString(_kToken);
    final u = sp.getString(_kUser);
    if (t != null) state = InstallerAuthState(token: t, username: u);
  }

  /// Returns true only for admin accounts.
  Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$apiBase/api/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>;
    if (user['role'] != 'admin') return false;

    final token = body['token'] as String;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, token);
    await sp.setString(_kUser, user['username'] as String);
    state = InstallerAuthState(token: token, username: user['username'] as String);
    return true;
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kUser);
    state = const InstallerAuthState();
  }
}

final installerAuthProvider =
    NotifierProvider<InstallerAuthController, InstallerAuthState>(
  InstallerAuthController.new,
);
