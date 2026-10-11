#!/usr/bin/env sh
# Archie Cloud — eenmalige VPS-inrichting (Ubuntu 22.04/24.04, als root).
# Zet Docker, WireGuard-hub (wg0), ip_forward en nftables klaar en start de stack.
set -eu
cd "$(dirname "$0")"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
die() { printf '\nFOUT: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Als root draaien: sudo ./setup-vps.sh"
[ -f .env ] || die "Kopieer .env.example naar .env en vul PUBLIC_IP, DOMAIN, TURN_SECRET, ENROLL_ADMIN_TOKEN in."

# .env inlezen (alleen KEY=VALUE regels)
set -a
# shellcheck disable=SC1091
. ./.env
set +a

WG_SUBNET="${WG_SUBNET:-10.80.0.0/16}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.80.0.1}"
WG_PORT="${WG_PORT:-51820}"
PREFIX="${WG_SUBNET#*/}"

bold "=== Archie Cloud VPS ==="

# ── Pakketten ────────────────────────────────────────────────────────────────
apt-get update -y
apt-get install -y wireguard-tools nftables curl ca-certificates
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || die "docker compose plugin ontbreekt"
ok "Docker en WireGuard aanwezig"

# ── WireGuard-hub ────────────────────────────────────────────────────────────
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/server.key ]; then
  umask 077
  wg genkey > /etc/wireguard/server.key
  wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub
  ok "Serversleutel aangemaakt"
fi
touch /etc/wireguard/peers.conf
chmod 600 /etc/wireguard/peers.conf

if [ ! -f /etc/wireguard/wg0.conf ]; then
  cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${WG_SERVER_ADDRESS}/${PREFIX}
ListenPort = ${WG_PORT}
PrivateKey = $(cat /etc/wireguard/server.key)
# Peers worden door de enrollment-service in peers.conf bijgehouden.
PostUp = wg addconf %i /etc/wireguard/peers.conf
EOF
  chmod 600 /etc/wireguard/wg0.conf
  ok "wg0.conf geschreven (${WG_SERVER_ADDRESS}/${PREFIX}, poort ${WG_PORT})"
fi

# Forwarding tussen hub-peers (installateur -> NUC) en vanaf Docker (Caddy/coturn -> NUC).
cat > /etc/sysctl.d/90-archie-cloud.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl -q -p /etc/sysctl.d/90-archie-cloud.conf

systemctl enable --now wg-quick@wg0
systemctl restart wg-quick@wg0
ok "wg0 actief"

# ── Firewall (nftables) ──────────────────────────────────────────────────────
# Docker beheert zijn eigen iptables-regels; wij voegen alleen een inbound-filter
# toe op de host en staan forwarding binnen het wg-subnet toe.
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet archie {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    tcp dport 22 accept
    tcp dport { 80, 443 } accept
    udp dport 443 accept
    udp dport { 3478, ${WG_PORT} } accept
    tcp dport 3478 accept
    udp dport 49160-49400 accept
    # Caddy (docker-bridge) -> enrollment-API op de host
    iifname { "docker0", "br-*" } tcp dport { 8090, 2019 } accept
    iifname "wg0" tcp dport 8090 accept
    iifname "wg0" udp dport 3478 accept
  }
  chain forward {
    type filter hook forward priority 0; policy accept;
    # Peers onderling alleen vanaf installateurs (10.80.255.0/24) naar NUC's.
    iifname "wg0" oifname "wg0" ip saddr ${WG_SUBNET%.*.*}.255.0/24 accept
    iifname "wg0" oifname "wg0" drop
  }
}
EOF
systemctl enable --now nftables
nft -f /etc/nftables.conf
ok "Firewall actief (22, 80, 443, 3478, ${WG_PORT}, relay 49160-49400)"

# ── Caddy: eerste Caddyfile zodat de bind-mount een bestand is ──────────────
mkdir -p data/caddy data/enroll
if [ ! -f data/caddy/Caddyfile ]; then
  cat > data/caddy/Caddyfile <<EOF
{
	admin 0.0.0.0:2019
}
https://enroll.${DOMAIN} {
	reverse_proxy host.docker.internal:8090
}
EOF
  ok "Start-Caddyfile geschreven"
fi

bold "Stack starten…"
docker compose up -d --build
ok "Caddy, coturn en enroll draaien"

bold "=== Klaar ==="
echo ""
echo "  Server public key : $(cat /etc/wireguard/server.pub)"
echo "  Enrollment        : https://enroll.${DOMAIN}/health"
echo "  Nieuwe klant      : docker compose exec enroll node cli.mjs new-code \"Naam\""
echo "  Installateur/ETS  : docker compose exec enroll node cli.mjs installer \"Naam\""
echo ""
