const kMinUserCodeLength = 4;

/// Client-side check before PUT /users or installer save.
/// New accounts must set `_new: true` and a `password` of at least 4 chars.
String? validateUsersLoginCredentials(List<Map<String, dynamic>> users) {
  final names = <String>[];
  for (final u in users) {
    final name = (u['username'] as String? ?? '').trim();
    if (name.isEmpty) return 'Elke gebruiker heeft een inlognaam nodig';
    names.add(name.toLowerCase());
    final code = u['password'] as String?;
    if (code != null &&
        code.isNotEmpty &&
        code.length < kMinUserCodeLength) {
      return 'Code van "$name" moet minstens $kMinUserCodeLength tekens zijn';
    }
    if (u['_new'] == true && (code == null || code.isEmpty)) {
      return 'Gebruiker "$name" heeft geen code';
    }
  }
  if (names.toSet().length != names.length) {
    return 'Inlognaam moet uniek zijn';
  }
  return null;
}

/// Copy for the API: trim names, drop client-only `_new`, omit empty codes.
List<Map<String, dynamic>> usersPayloadForSave(
  List<Map<String, dynamic>> users,
) {
  return [
    for (final u in users)
      () {
        final copy = Map<String, dynamic>.from(u);
        copy['username'] = (copy['username'] as String? ?? '').trim();
        copy.remove('_new');
        final p = copy['password'];
        if (p is! String || p.isEmpty) copy.remove('password');
        return copy;
      }(),
  ];
}

void clearNewUserFlags(List<Map<String, dynamic>> users) {
  for (final u in users) {
    u.remove('_new');
    u.remove('password');
  }
}
