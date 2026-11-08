#!/bin/sh
# Docker zet de FORWARD-policy op DROP. Verkeer tussen WireGuard-peers
# (installateurslaptop → NUC) valt daardoor weg, ook al laat nftables het toe.
#
# go2rtc luistert op de NUC op :8555, zonder login. Deze regels laten alleen
# dat pad door, voor elk huis in WG_SUBNET:
#   bron  = installateurs (x.x.255.0/24)
#   doel  = het WG-net
#   poort = 8555
#   alleen interfaces wg0 → wg0
#
# Geen DNAT en geen accept vanaf het publieke internet. Telefoons buitenshuis
# gaan via coturn (host-netwerk, tijdelijk geheim, peers alleen in dit WG-net).
# Een publieke forward naar één NUC hoort hier niet: die deelt één poort en
# heeft geen authenticatie.
set -eu

WG_SUBNET="${WG_SUBNET:-10.80.0.0/16}"
# Zelfde afleiding als setup-vps.sh: 10.80.0.0/16 → 10.80.255.0/24.
INSTALLER="${WG_SUBNET%.*.*}.255.0/24"
case "$INSTALLER" in
  *.*.255.0/24) ;;
  *)
    echo "WG_SUBNET ongeldig: $WG_SUBNET" >&2
    exit 1
    ;;
esac

i=0
while ! iptables -L DOCKER-USER -n >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 30 ]; then
    echo "DOCKER-USER ontbreekt na 30s (Docker nog niet klaar)" >&2
    exit 1
  fi
  sleep 1
done

add() {
  iptables -C DOCKER-USER "$@" -m comment --comment archie-8555 -j ACCEPT 2>/dev/null \
    || iptables -I DOCKER-USER 1 "$@" -m comment --comment archie-8555 -j ACCEPT
}

# Vorige versie: elk doorgestuurd pakket van of naar 10.80.0.2:8555.
# iptables bewaart dat als 10.80.0.2/32 en -m tcp/-m udp, dus een -D met de
# oorspronkelijke tekst mist. Verwijder wat er echt staat.
old="$(iptables -S DOCKER-USER)"
printf '%s\n' "$old" | while IFS= read -r line; do
  case "$line" in
    *"-d 10.80.0.2"*8555*|*" -s 10.80.0.2"*8555*)
      spec=${line#-A DOCKER-USER }
      # shellcheck disable=SC2086
      iptables -D DOCKER-USER $spec || true
      ;;
  esac
done

for proto in tcp udp; do
  add -i wg0 -o wg0 -s "$INSTALLER" -d "$WG_SUBNET" -p "$proto" --dport 8555
  add -i wg0 -o wg0 -s "$WG_SUBNET" -d "$INSTALLER" -p "$proto" --sport 8555 \
    -m conntrack --ctstate ESTABLISHED,RELATED
done
