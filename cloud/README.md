# Archie Cloud (VPS)

Eén server voor alle klanten. Elke NUC houdt zelf een WireGuard-verbinding
naar deze server open. Hierdoor werkt de app buitenshuis via
`https://<klant-id>.archiecloud.nl` zonder poorten op de router van de klant,
zonder VPN-app op de telefoon, en kan de installateur met ETS programmeren.

```
Telefoon 4G ──HTTPS──▶ Caddy ──wg0──▶ NUC :4000  (app, API, WebSocket)
Telefoon 4G ──TURN───▶ coturn ─wg0──▶ NUC :8555  (camera/intercom WebRTC)
ETS laptop  ──wg0────▶ hub ───wg0──▶ NUC :3671  (knxd, optioneel)
```

## Wat je nodig hebt

- Een VPS (Hetzner CX22 of vergelijkbaar, Ubuntu 24.04), vast IPv4.
- Domein `archiecloud.nl` met DNS:
  - `A   enroll.archiecloud.nl  -> <vps-ip>`
  - `A   turn.archiecloud.nl    -> <vps-ip>`
  - `A   *.archiecloud.nl       -> <vps-ip>`
  - `A   archiecloud.nl         -> <vps-ip>` (hoofddomein: Android haalt daar
    `/.well-known/assetlinks.json` op zodat een koppellink de app opent)
- Poorten open op de VPS: 80/tcp, 443/tcp, 3478/udp+tcp, 51820/udp, 49160–49400/udp, SSH.

## Koppellink opent de app (App Links / Universal Links)

De koppellink is `https://<huis>.archiecloud.nl/pair?code=...`. Zonder app
opent de browser de web-app. Met de app geïnstalleerd opent het OS de app
direct, mits het domein de app "erkent":

- Android: zet `ANDROID_CERT_SHA256` in `.env` op de SHA256 van het
  signeer-certificaat van de APK (`keytool -list -v -keystore <jks>`). Caddy
  serveert dan `assetlinks.json` op het hoofddomein en op elk klantdomein.
- iOS: zet `APPLE_TEAM_ID` (en `IOS_BUNDLE_ID`). Vereist daarnaast de
  Associated Domains-entitlement `applinks:*.archiecloud.nl` in de iOS-build.

Na wijzigen: `docker compose up -d enroll` (de enroll-service schrijft de
Caddyfile opnieuw bij start).

## Installatie (eenmalig)

```bash
git clone <deze repo> archie && cd archie/cloud
cp .env.example .env            # vul PUBLIC_IP, DOMAIN, TURN_SECRET, ENROLL_ADMIN_TOKEN
sudo ./setup-vps.sh             # docker, wireguard (wg0 = 10.80.0.1/16), ip_forward, nftables
docker compose up -d --build
```

`setup-vps.sh` maakt `/etc/wireguard/wg0.conf` met een serversleutel en zet
forwarding aan. Peers worden daarna door de enrollment-service toegevoegd met
`wg set`; het script schrijft ze ook weg naar `data/peers/` zodat een reboot
ze terugzet.

## Een klant toevoegen

Op de VPS:

```bash
docker compose exec enroll node cli.mjs new-code "Fam. Jansen"
# -> 7K3M-Q8ZD   (10 minuten geldig, eenmalig)
```

Op de NUC van de klant draait `./installeer.sh`; die vraagt "Remote toegang via
Archie Cloud?" en dan deze code. Het script:

1. maakt een WireGuard-sleutelpaar,
2. meldt zich aan bij `https://enroll.archiecloud.nl/enroll`,
3. krijgt `serverId`, `https://<serverId>.archiecloud.nl`, een wg-adres en het TURN-geheim,
4. schrijft `/etc/wireguard/wg0.conf`, `systemctl enable --now wg-quick@wg0`,
5. zet `SERVER_ID`, `REMOTE_URL`, `WG_ADDRESS`, `TURN_HOST`, `TURN_SECRET` in `docker/.env`.

Vanaf dan toont `/api/health` op de NUC zijn cloud-URL en pakt de app die
automatisch over zodra de telefoon niet thuis is.

## Installateur / ETS

```bash
docker compose exec enroll node cli.mjs installer "Piet"
# -> print een wg-config voor de laptop (AllowedIPs = 10.80.0.0/16)
```

ETS: interface handmatig toevoegen op `<wg-adres-van-de-NUC>:3671`. Op de NUC
moet daarvoor het `knxd`-profiel aan staan (`docker compose --profile knxd up -d`),
dat de KNX IP-interface deelt met ETS. Zonder knxd: alleen als de interface
meerdere tunnels aankan en je de LAN-route van die klant apart toevoegt
(let op: overlappende 192.168.x-netten tussen klanten kunnen niet samen
gerouteerd worden; daarom standaard knxd op het wg-adres).

## Overzicht

```bash
docker compose exec enroll node cli.mjs list
docker compose exec enroll node cli.mjs revoke <serverId>
```

## Kosten en grenzen

- Bediening en bellen kosten per huis vrijwel niets. Camera's kijken buitenshuis
  loopt via coturn (ongeveer 2 Mbit/s per stream). Meet het verkeer voordat je
  limieten of een aparte prijs invoert.
- Eén VPS is één storingspunt voor remote. Thuis blijft alles werken.
- Certificaten: de enrollment-service schrijft per klant een site-blok in de
  Caddyfile en herlaadt Caddy; Caddy haalt dan meteen een certificaat op
  (HTTP-01). Geen DNS-API of wildcard-plugin nodig.
