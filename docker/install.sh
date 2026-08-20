#!/usr/bin/env sh
# Archie OS — installatie voor NUC / Proxmox (Ubuntu-VM)
# Bedoeld voor iemand zonder programmeerkennis: antwoorden met Enter / j / n.
set -eu
cd "$(dirname "$0")"

ROOT="$(CDPATH= cd .. && pwd)"
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die() { printf '\nFOUT: %s\n' "$*" >&2; exit 1; }

ask_yn() {
  # $1 = vraag, default ja
  printf '%s [J/n] ' "$1"
  read -r ans || ans=
  case "${ans:-J}" in
    n|N|nee|Nee|NEE) return 1 ;;
    *) return 0 ;;
  esac
}

detect_lan_ip() {
  ip=
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  fi
  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    # Fallback zonder openssl
    date +%s%N | tr -cd 'a-f0-9' | head -c 48
  fi
}

bold "=== Archie OS installatie ==="
echo "Deze wizard zet de smart-home software klaar op deze computer."
echo "Eerste keer: bouw kan 10–20 minuten duren. Even laten staan."
echo ""

# ── Docker ──────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker is nog niet geïnstalleerd."
  if ask_yn "Docker nu automatisch installeren? (aanbevolen)"; then
    if [ "$(id -u)" -eq 0 ]; then
      curl -fsSL https://get.docker.com | sh
    else
      curl -fsSL https://get.docker.com | sudo sh
      sudo usermod -aG docker "$USER" || true
    fi
    ok "Docker geïnstalleerd."
    if ! docker info >/dev/null 2>&1; then
      warn "Je moet even uit- en inloggen (of de VM herstarten) zodat Docker zonder sudo werkt."
      warn "Daarna dit script opnieuw starten:  cd docker && ./install.sh"
      exit 0
    fi
  else
    die "Installeer Docker handmatig (https://docs.docker.com/engine/install/ubuntu/) en start dit script opnieuw."
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  die "Docker Compose plugin ontbreekt. Op Ubuntu meestal: sudo apt install docker-compose-plugin"
fi
ok "Docker is beschikbaar"

DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
    warn "Docker draait via sudo (gebruiker zit nog niet in de docker-groep)."
  else
    die "Geen rechten op Docker. Log opnieuw in na installatie, of: sudo usermod -aG docker \$USER"
  fi
fi

# ── Mappen ──────────────────────────────────────────────────────────────────
mkdir -p "$ROOT/config" ./go2rtc ./data
ok "Mappen klaar (config, data, go2rtc)"

# ── .env ────────────────────────────────────────────────────────────────────
LAN_IP="$(detect_lan_ip)"
if ! test -f .env; then
  SECRET="$(random_secret)"
  cat > .env <<EOF
# Automatisch aangemaakt door install.sh — niet delen.
JWT_SECRET=${SECRET}
MEDIA_BASE_URL=http://127.0.0.1:1984
PUBLIC_API_BASE=http://${LAN_IP}:4000
GITHUB_REPO=Archie-Automation/visualisatie
EOF
  ok ".env aangemaakt (geheime sleutel + LAN-adres ${LAN_IP})"
  warn "Repo is privé: zet GITHUB_TOKEN in docker/.env voor versiemeldingen (GitHub → Settings → Developer settings → PAT)."
else
  ok "Bestaande .env behouden"
  if ! grep -q '^GITHUB_REPO=' .env 2>/dev/null; then
    printf '\nGITHUB_REPO=Archie-Automation/visualisatie\n' >> .env
    ok "GITHUB_REPO toegevoegd aan .env"
  fi
  # Vul PUBLIC_API_BASE alleen als die nog leeg/uitgecommentarieerd is
  if ! grep -q '^PUBLIC_API_BASE=http' .env 2>/dev/null; then
    if ask_yn "PUBLIC_API_BASE zetten op http://${LAN_IP}:4000?"; then
      if grep -q '^PUBLIC_API_BASE=' .env; then
        # shellcheck disable=SC2016
        sed -i.bak "s|^PUBLIC_API_BASE=.*|PUBLIC_API_BASE=http://${LAN_IP}:4000|" .env
      else
        printf '\nPUBLIC_API_BASE=http://%s:4000\n' "$LAN_IP" >> .env
      fi
      ok "PUBLIC_API_BASE bijgewerkt"
    fi
  fi
fi

# ── Huisconfig ──────────────────────────────────────────────────────────────
if ! test -f "$ROOT/config/house.json"; then
  test -f "$ROOT/config/house.empty.json" || die "config/house.empty.json ontbreekt in de map."
  cp "$ROOT/config/house.empty.json" "$ROOT/config/house.json"
  ok "Leeg huis aangemaakt (nog geen apparaten)"
  NEW_HOUSE=1
else
  ok "Bestaande house.json behouden (niet overschreven)"
  NEW_HOUSE=0
fi

# ── Start ───────────────────────────────────────────────────────────────────
bold "Software bouwen en starten…"
echo "Dit kan de eerste keer lang duren. Niet afbreken."
echo ""

# Oude Luxe KNX-container/image (vóór hernoeming naar Archie OS) weghalen.
if $DOCKER ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'luxe-knx-stack'; then
  $DOCKER rm -f luxe-knx-stack >/dev/null 2>&1 || true
  ok "Oude container luxe-knx-stack verwijderd"
fi
if $DOCKER image inspect luxe-knx-stack:latest >/dev/null 2>&1; then
  $DOCKER image rm luxe-knx-stack:latest >/dev/null 2>&1 || true
  ok "Oude image luxe-knx-stack:latest verwijderd"
fi

$DOCKER compose --env-file .env up -d --build

# ── Update-agent (server bijwerken vanaf de tablet) ─────────────────────────
install_update_agent() {
  agent="$ROOT/docker/update-agent.sh"
  if [ ! -f "$agent" ]; then
    warn "update-agent.sh ontbreekt — tablet-update is niet beschikbaar"
    return
  fi
  chmod +x "$agent" || true
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl ontbreekt — update-agent niet als service gezet"
    return
  fi
  if ! command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    warn "Geen sudo — update-agent niet als service gezet"
    return
  fi
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
  fi
  owner="$(stat -c '%U' "$ROOT" 2>/dev/null || echo root)"
  extra_groups=""
  if getent group docker >/dev/null 2>&1; then
    extra_groups="SupplementaryGroups=docker"
  fi
  unit=/etc/systemd/system/archie-os-update-agent.service
  $SUDO tee "$unit" >/dev/null <<EOF
[Unit]
Description=Archie OS GitHub update agent
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$owner
$extra_groups
WorkingDirectory=$ROOT
Environment=HOME=$(getent passwd "$owner" 2>/dev/null | cut -d: -f6 || echo /root)
ExecStart=/bin/sh $agent
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now archie-os-update-agent.service
  ok "Update-agent actief (server bijwerken vanaf de tablet, als admin)"
}
install_update_agent

bold "=== Klaar ==="
echo ""
echo "  Open op telefoon of PC (zelfde wifi als de NUC):"
echo ""
echo "      http://${LAN_IP}:4000/"
echo ""
if [ "$NEW_HOUSE" -eq 1 ]; then
  echo "  Eerste login:"
  echo "      gebruiker:  admin"
  echo "      wachtwoord: admin"
  echo ""
  echo "  Daarna: Instellingen / Installer → wachtwoord wijzigen,"
  echo "  etages en apparaten toevoegen."
else
  echo "  Gebruik je bestaande login uit dit huis."
fi
echo ""
echo "  Controleren of alles draait:"
echo "      curl -s http://127.0.0.1:4000/api/health"
echo "      curl -s http://127.0.0.1:4000/api/version"
echo ""
echo "  Later updaten: in de app (admin) Server bijwerken, of:"
echo "      cd docker && ./install.sh"
echo ""
