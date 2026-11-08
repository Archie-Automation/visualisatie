#!/bin/sh
# Nieuw wachtwoord voor een account, alleen op deze NUC.
# Het internet en het huis-wifi kunnen dit niet. De app hoeft niet open.
#
#   cd docker && ./wachtwoord.sh admin
set -eu
cd "$(dirname "$0")"

user="${1:-}"
if [ -z "$user" ]; then
  printf 'Gebruik: ./wachtwoord.sh <gebruikersnaam>\n' >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'python3 ontbreekt op deze machine.\n' >&2
  exit 1
}

restore_echo() { stty echo 2>/dev/null || true; }
trap restore_echo EXIT INT TERM
if [ -t 0 ]; then stty -echo; fi
printf 'Nieuw wachtwoord: '
read -r pass
printf '\nHerhaal: '
read -r again
restore_echo
printf '\n'

if [ "$pass" != "$again" ]; then
  printf 'De twee wachtwoorden zijn niet gelijk.\n' >&2
  exit 1
fi

python3 - "$user" "$pass" << 'PY'
import json, sys, urllib.error, urllib.request
user, password = sys.argv[1], sys.argv[2]
body = json.dumps({"username": user, "password": password}).encode()
req = urllib.request.Request(
    "http://127.0.0.1:4000/api/auth/local-password",
    data=body,
    headers={"content-type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=8) as res:
        res.read()
except urllib.error.HTTPError as err:
    raw = err.read().decode("utf-8", "replace")
    try:
        msg = json.loads(raw).get("error") or raw
    except json.JSONDecodeError:
        msg = raw or str(err.code)
    sys.stderr.write(str(msg) + "\n")
    sys.exit(1)
PY

printf 'Wachtwoord van %s is gezet. Oude sessies van dat account zijn uitgelogd.\n' "$user"
