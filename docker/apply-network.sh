#!/bin/sh
# LAN-adres van de NUC. Alleen via de update-agent, als root op de host.
# Een verkeerd adres draait de agent terug als de installateur het niet
# binnen 2 minuten opent.
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
DATA="$SCRIPT_DIR/data"
REQ="$DATA/network-request.json"
PENDING="$DATA/network-pending.json"
CONFIRM="$DATA/network-confirm.json"
ERR="$DATA/network-error.json"
BACKUP=/var/lib/archie-os/netplan-backup

write_error() {
  msg="$1"
  python3 - "$ERR" "$msg" <<'PY'
import json, os, sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(json.dumps({"message": sys.argv[2]}) + "\n", encoding="utf-8")
os.chmod(p, 0o666)
PY
  echo "network error: $msg" >&2
}

restore_backup() {
  if [ ! -d "$BACKUP" ]; then
    return 0
  fi
  find /etc/netplan -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -delete 2>/dev/null || true
  cp -a "$BACKUP"/. /etc/netplan/ 2>/dev/null || true
  netplan apply || true
}

if [ "${1:-}" = "revert" ]; then
  echo "network revert"
  restore_backup
  rm -f "$PENDING" "$CONFIRM"
  write_error "Het nieuwe adres reageerde niet. Het vorige adres is teruggezet."
  exit 0
fi

if [ ! -f "$REQ" ]; then
  echo "geen network-request" >&2
  exit 1
fi

parsed=$(python3 - "$REQ" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
mode = str(d.get("mode") or "")
if mode not in ("dhcp", "static"):
    sys.exit(2)
print(mode)
if mode == "static":
    print(str(d.get("address") or "").strip())
    print(int(d.get("prefix")))
    print(str(d.get("gateway") or "").strip())
    dns = d.get("dns") or []
    if not isinstance(dns, list) or not dns:
        dns = [str(d.get("gateway") or "").strip()]
    print(",".join(str(x).strip() for x in dns[:2] if str(x).strip()))
PY
) || {
  rm -f "$REQ"
  write_error "Het netwerkverzoek is ongeldig."
  exit 1
}
rm -f "$REQ" "$ERR"

MODE=$(printf '%s\n' "$parsed" | sed -n '1p')
ADDR=$(printf '%s\n' "$parsed" | sed -n '2p')
PREFIX=$(printf '%s\n' "$parsed" | sed -n '3p')
GW=$(printf '%s\n' "$parsed" | sed -n '4p')
DNS=$(printf '%s\n' "$parsed" | sed -n '5p')

IFACE=$(ip -4 route show default | awk '
  {
    for (i = 1; i <= NF; i++) if ($i == "dev") {
      dev = $(i + 1)
      if (dev != "docker0" && dev !~ /^br-/ && dev !~ /^veth/ && dev !~ /^docker/) {
        print dev
        exit
      }
    }
  }
')
case "$IFACE" in
  ""|*[!A-Za-z0-9._:-]*)
    write_error "Geen netwerkkaart met een standaardroute gevonden."
    exit 1
    ;;
esac

command -v netplan >/dev/null 2>&1 || {
  write_error "netplan ontbreekt op deze server."
  exit 1
}

PREV=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n 1 | cut -d/ -f1)

rm -rf "$BACKUP"
mkdir -p "$BACKUP" /etc/netplan
cp -a /etc/netplan/. "$BACKUP/" 2>/dev/null || true
find /etc/netplan -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -delete

{
  echo "network:"
  echo "  version: 2"
  echo "  ethernets:"
  echo "    ${IFACE}:"
  if [ "$MODE" = "dhcp" ]; then
    echo "      dhcp4: true"
  else
    echo "      dhcp4: false"
    echo "      addresses:"
    echo "        - ${ADDR}/${PREFIX}"
    echo "      routes:"
    echo "        - to: default"
    echo "          via: ${GW}"
    echo "      nameservers:"
    echo "        addresses:"
    oldifs=$IFS
    IFS=,
    for d in $DNS; do
      [ -n "$d" ] && echo "          - ${d}"
    done
    IFS=$oldifs
  fi
} > /etc/netplan/99-archie-os.yaml
chmod 644 /etc/netplan/99-archie-os.yaml

if command -v timeout >/dev/null 2>&1; then
  if ! timeout 30 netplan apply; then
    restore_backup
    write_error "Het nieuwe adres kon niet gezet worden. Het vorige adres blijft."
    exit 1
  fi
elif ! netplan apply; then
  restore_backup
  write_error "Het nieuwe adres kon niet gezet worden. Het vorige adres blijft."
  exit 1
fi

NEW=""
i=0
while [ "$i" -lt 12 ]; do
  NEW=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n 1 | cut -d/ -f1)
  if [ "$MODE" = "static" ] && [ "$NEW" = "$ADDR" ]; then
    break
  fi
  if [ "$MODE" = "dhcp" ] && [ -n "$NEW" ]; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$MODE" = "static" ]; then
  NEW="$ADDR"
fi
if [ -z "$NEW" ]; then
  NEW="$PREV"
fi

python3 - "$PENDING" "$MODE" "$NEW" "$PREV" <<'PY'
import json, os, sys, time
from pathlib import Path
p = Path(sys.argv[1])
body = {
    "applied": True,
    "mode": sys.argv[2],
    "address": sys.argv[3],
    "previousAddress": sys.argv[4],
    "since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "deadlineEpoch": int(time.time()) + 120,
}
p.write_text(json.dumps(body, indent=2) + "\n", encoding="utf-8")
os.chmod(p, 0o666)
PY
echo "network applied mode=$MODE addr=$NEW prev=$PREV iface=$IFACE"
