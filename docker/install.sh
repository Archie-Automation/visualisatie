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
mkdir -p "$ROOT/config" ./go2rtc ./data ./data/asterisk ./data/certs
ok "Mappen klaar (config, data, go2rtc)"

# ── Git (tablet/telefoon “Server bijwerken”) ────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
  warn "Git ontbreekt — nodig om vanaf tablet/telefoon te updaten."
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -y && apt-get install -y git
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y git
  else
    warn "Installeer git handmatig: sudo apt install git"
  fi
fi
if command -v git >/dev/null 2>&1; then
  ok "Git is beschikbaar"
else
  warn "Zonder git valt de tablet-update terug op een GitHub-zip; curl moet dan werken."
fi

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

# ── Server-id (app herkent deze NUC via LAN én cloud) ───────────────────────
set_env_var() {
  # $1 = KEY, $2 = VALUE; vervangt of voegt toe in .env
  key="$1"; val="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    # shellcheck disable=SC2016
    sed -i.bak "s|^${key}=.*|${key}=${val}|" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}
if ! grep -q '^SERVER_ID=.' .env 2>/dev/null; then
  set_env_var SERVER_ID "$(random_secret | head -c 8)"
  ok "SERVER_ID aangemaakt"
fi

# ── Remote toegang via Archie Cloud (optioneel) ─────────────────────────────
# Eén eenmalige code van de beheerder; daarna houdt deze NUC zelf een
# WireGuard-verbinding naar de VPS open. Geen poorten, geen VPN-app.
ARCHIE_CLOUD_ENROLL="${ARCHIE_CLOUD_ENROLL:-https://enroll.archiecloud.nl}"
enroll_cloud() {
  if ! command -v wg >/dev/null 2>&1; then
    warn "WireGuard ontbreekt — installeren…"
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update -y && apt-get install -y wireguard-tools
    else
      sudo apt-get update -y && sudo apt-get install -y wireguard-tools
    fi
  fi
  command -v wg >/dev/null 2>&1 || { warn "wireguard-tools niet geïnstalleerd; remote overgeslagen"; return 1; }
  command -v python3 >/dev/null 2>&1 || { warn "python3 ontbreekt; remote overgeslagen"; return 1; }

  printf 'Enrollment-code (bijv. 7K3M-Q8ZD): '
  read -r code || code=
  [ -n "$code" ] || { warn "Geen code; remote overgeslagen"; return 1; }

  umask 077
  priv="$(wg genkey)"
  pub="$(printf '%s' "$priv" | wg pubkey)"
  host="$(hostname 2>/dev/null || echo nuc)"
  body="$(printf '{"code":"%s","publicKey":"%s","hostname":"%s"}' "$code" "$pub" "$host")"
  resp="$(curl -fsS --max-time 20 -H 'content-type: application/json' -d "$body" "${ARCHIE_CLOUD_ENROLL}/enroll" 2>&1)" || {
    warn "Aanmelden mislukt: ${resp}"
    return 1
  }
  # JSON → shell-variabelen
  eval "$(printf '%s' "$resp" | python3 -c '
import json, sys, shlex
d = json.load(sys.stdin)
if "error" in d:
    print("ENROLL_ERR=" + shlex.quote(d["error"])); sys.exit(0)
wg = d["wg"]; turn = d.get("turn", {})
for k, v in {
  "E_SERVER_ID": d["serverId"], "E_REMOTE_URL": d["remoteUrl"],
  "E_WG_ADDR": wg["address"], "E_WG_PUB": wg["serverPublicKey"],
  "E_WG_EP": wg["endpoint"], "E_WG_ALLOWED": wg["allowedIps"],
  "E_WG_KA": str(wg.get("persistentKeepalive", 25)),
  "E_TURN_HOST": turn.get("host", ""), "E_TURN_SECRET": turn.get("secret", ""),
}.items():
    print(k + "=" + shlex.quote(str(v)))
')"
  if [ -n "${ENROLL_ERR:-}" ]; then
    warn "Aanmelden geweigerd: ${ENROLL_ERR}"
    return 1
  fi

  SUDO=""
  [ "$(id -u)" -eq 0 ] || SUDO="sudo"
  $SUDO mkdir -p /etc/wireguard
  $SUDO sh -c "umask 077; cat > /etc/wireguard/wg0.conf" <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${E_WG_ADDR}

[Peer]
PublicKey = ${E_WG_PUB}
Endpoint = ${E_WG_EP}
AllowedIPs = ${E_WG_ALLOWED}
PersistentKeepalive = ${E_WG_KA}
EOF
  $SUDO systemctl enable --now wg-quick@wg0 >/dev/null 2>&1 || warn "wg-quick@wg0 starten mislukt; controleer /etc/wireguard/wg0.conf"
  $SUDO systemctl restart wg-quick@wg0 >/dev/null 2>&1 || true

  # SERVER_ID blijft wat hij was: telefoons die deze NUC al kennen, blijven kloppen.
  set_env_var REMOTE_URL "$E_REMOTE_URL"
  set_env_var WG_ADDRESS "${E_WG_ADDR%/*}"
  set_env_var TURN_HOST "$E_TURN_HOST"
  set_env_var TURN_SECRET "$E_TURN_SECRET"
  REMOTE_URL_SHOWN="$E_REMOTE_URL"
  ok "Remote toegang actief: ${E_REMOTE_URL}"
  return 0
}

REMOTE_URL_SHOWN="$(grep '^REMOTE_URL=' .env 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' || true)"
if [ -z "$REMOTE_URL_SHOWN" ]; then
  if ask_yn "Remote toegang via Archie Cloud inschakelen? (code van de beheerder nodig)"; then
    enroll_cloud || true
  fi
else
  ok "Remote toegang al ingesteld: ${REMOTE_URL_SHOWN}"
fi

# ZIP/USB-install heeft geen .git — dan faalt de tablet-knop. Eenmalig koppelen.
if command -v git >/dev/null 2>&1 && [ ! -d "$ROOT/.git" ]; then
  git_repo="$(grep '^GITHUB_REPO=' .env 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' | sed 's/^["'\'']//;s/["'\'']$//;s/[[:space:]]*$//' || true)"
  [ -n "$git_repo" ] || git_repo="Archie-Automation/visualisatie"
  git -C "$ROOT" init >/dev/null
  git -C "$ROOT" remote remove origin >/dev/null 2>&1 || true
  git -C "$ROOT" remote add origin "https://github.com/${git_repo}.git"
  ok "Map gekoppeld aan GitHub — ‘Server bijwerken’ in de app haalt hierna code op"
fi

# ── Huisconfig ──────────────────────────────────────────────────────────────
# house.json staat niet in git. Een `git pull` die het bestand ooit uit de
# index haalde kan het lokaal wissen; daarom altijd een kopie in docker/data.
HOUSE_KEEP="./data/house.json.keep"
if test -f "$ROOT/config/house.json"; then
  cp -a "$ROOT/config/house.json" "$HOUSE_KEEP" 2>/dev/null || true
  ok "Bestaande house.json behouden (niet overschreven)"
  NEW_HOUSE=0
elif test -s "$HOUSE_KEEP"; then
  cp -a "$HOUSE_KEEP" "$ROOT/config/house.json"
  ok "house.json teruggezet uit docker/data (was na update verdwenen)"
  NEW_HOUSE=0
else
  test -f "$ROOT/config/house.empty.json" || die "config/house.empty.json ontbreekt in de map."
  cp "$ROOT/config/house.empty.json" "$ROOT/config/house.json"
  ok "Leeg huis aangemaakt (nog geen apparaten)"
  NEW_HOUSE=1
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

# Spotify-callback op :4443 (HTTPS). Zonder deze regel blokkeert UFW de terugkeer.
if command -v ufw >/dev/null 2>&1; then
  SUDO_UFW=""
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO_UFW="sudo"
  fi
  $SUDO_UFW ufw status 2>/dev/null | grep -q "Status: active" && \
    $SUDO_UFW ufw allow 4443/tcp comment "Archie OS Spotify HTTPS" >/dev/null 2>&1 || true
  $SUDO_UFW ufw status 2>/dev/null | grep -q "Status: active" && \
    $SUDO_UFW ufw allow 5060/udp comment "Archie OS SIP" >/dev/null 2>&1 || true
  $SUDO_UFW ufw status 2>/dev/null | grep -q "Status: active" && \
    $SUDO_UFW ufw allow 8089/tcp comment "Archie OS SIP WSS" >/dev/null 2>&1 || true
fi

# Asterisk draait in knx-stack; --remove-orphans ruimt de oude losse container op.
$DOCKER compose --env-file .env up -d --build --remove-orphans knx-stack

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
  $SUDO systemctl enable archie-os-update-agent.service
  $SUDO systemctl restart archie-os-update-agent.service
  ok "Update-agent actief (server bijwerken vanaf de tablet, als admin)"
}
install_update_agent

bold "=== Klaar ==="
echo ""
echo "  Open op telefoon of PC (zelfde wifi als de NUC):"
echo ""
echo "      http://${LAN_IP}:4000/"
echo ""
if [ -n "${REMOTE_URL_SHOWN:-}" ]; then
  echo "  Buitenshuis (de app wisselt zelf):"
  echo ""
  echo "      ${REMOTE_URL_SHOWN}"
  echo ""
fi
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
