# Installatie op Proxmox (NUC) — zonder programmeerkennis

Doel: de Archie OS-app draait op een **Ubuntu-VM in Proxmox**. Op telefoon/PC open je daarna een website-adres. Geen App Store nodig.

**Proxmox `:8006` is niet de app** — dat is alleen de Proxmox-beheerpagina. De app luistert op poort **4000** van de Ubuntu-VM (`http://<vm-ip>:4000`).

Cloudflare (buitenshuis / 5G) komt in een latere stap.

---

## Wat je nodig hebt

- NUC met **Proxmox**
- Je huis-netwerk (zelfde wifi/LAN als KNX, camera’s, Sonos)
- ± 20 minuten de eerste keer (download + bouw)

---

## Stap 1 — Ubuntu-VM in Proxmox maken

1. In Proxmox: **Create VM**.
2. ISO: **Ubuntu Server 24.04** (of Desktop — Server is genoeg).
3. Netwerk: **bridge naar je LAN** (vaak `vmbr0`) — niet alleen NAT.
4. Resources (richtlijn): **2 CPU**, **4–8 GB RAM**, **40 GB disk**.
5. Installeer Ubuntu; maak één gebruiker aan (bijv. `knx`).
6. Noteer het **IP-adres** van de VM (of zet een vast IP in de router).

Controle: vanaf je PC moet je de VM kunnen pingen op dat IP.

---

## Stap 2 — Software downloaden (GitHub)

Repo: [Archie-Automation/visualisatie](https://github.com/Archie-Automation/visualisatie)

### Optie A — ZIP (eenvoudigst)

1. Open op de PC: https://github.com/Archie-Automation/visualisatie  
2. Groene knop **Code** → **Download ZIP**  
3. Pak uit, kopieer de map naar de VM (USB, scp, gedeelde map) als bijv. `~/KNX-app`

Of op de VM (als die internet heeft):

```bash
sudo apt update
sudo apt install -y unzip curl
cd ~
curl -L -o visualisatie.zip https://github.com/Archie-Automation/visualisatie/archive/refs/heads/main.zip
unzip visualisatie.zip
mv visualisatie-main KNX-app
cd ~/KNX-app
```

(Bij een privé-repo: inloggen op GitHub / token gebruiken, of USB vanaf een PC waar je wél bij kunt.)

### Optie B — Git

```bash
sudo apt update
sudo apt install -y git curl
git clone https://github.com/Archie-Automation/visualisatie.git ~/KNX-app
cd ~/KNX-app
```

### Optie C — USB-stick

Kopieer de hele projectmap naar de VM, open een terminal in die map.

---

## Stap 3 — Installeren (één script)

```bash
chmod +x installeer.sh docker/install.sh
./installeer.sh
```

Het script:

- vraagt of Docker geïnstalleerd mag worden (antwoord **J**);
- maakt zelf een geheime sleutel (`.env`);
- maakt een **leeg huis** als er nog geen `house.json` is;
- bouwt en start de software;
- toont aan het eind het adres, bijv. `http://192.168.1.50:4000/`.

Eerste keer: **10–20 minuten** laten staan. Niet afbreken.

Als het script zegt dat je opnieuw moet inloggen na Docker: VM even herstarten of uitloggen/inloggen, daarna `./installeer.sh` nog eens.

---

## Stap 4 — App openen

1. Telefoon of PC op **dezelfde wifi/LAN**.
2. Browser: het adres uit het script (`http://…:4000/`).
3. Nieuw huis: login **admin** / **admin**.
4. Direct wachtwoord wijzigen via de Installer in de app.
5. iPhone: deel-menu → **Zet op beginscherm**.

---

## Nieuwe versie op GitHub (automatische melding)

De app vraagt de server: “draait er iets nieuws op GitHub?”

| Situatie | Wat je ziet |
|----------|-------------|
| **Server is bij** (zelfde of nieuwer dan GitHub) | Geen banner (tenzij tablet-APK achterloopt — zie hieronder) |
| **Nieuwere release/tag op GitHub** | Banner: *Nieuwe versie op GitHub (…)* → knop **Bekijken** + hint `./installeer.sh` |
| **Telefoon toont oude cache** terwijl server al nieuw is | Banner: *Vernieuw de app* |
| **Android-tablet: nieuwere Release mét APK-asset** | Banner: *Nieuwe app-versie…* → **Installeren** (download via NUC, Android-installprompt) |

Standaard repo: `Archie-Automation/visualisatie` (`.env`: `GITHUB_REPO`).

**Belangrijk:** die repo is **privé**. Zonder token ziet de server geen releases → geen banner / geen APK-download.

1. GitHub → Settings → Developer settings → Personal access tokens  
2. Token met recht `repo` (read)  
3. In `docker/.env`:
   ```
   GITHUB_TOKEN=ghp_...
   ```
4. Stack herstarten: `./installeer.sh`

### Android-tablet (geen Play Store): update vanaf GitHub

De native app update **niet** door alleen code te pushen. Je hebt een **GitHub Release** nodig met een **`.apk` als asset**. De tablet haalt die APK via de NUC (`/api/app/android.apk`); de GitHub-token blijft op de server.

1. Eerste keer: APK sideloaden (USB/`adb install`) met ontwikkelaarsopties.  
2. Bouw een release-APK (versie = `pubspec.yaml`, zelfde als de release-tag):
   ```powershell
   cd app
   .\build_release_apk.ps1 -ApiBase http://192.168.x.x:4000
   ```
   (`ApiBase` is alleen de *default*; in de app kun je het serveradres op het loginscherm (of splash) wijzigen.)
3. Maak op GitHub een **Release** (tag bv. `v0.3.0`) en upload `build/app/outputs/flutter-apk/app-release.apk` (of hernoem naar `archie-os.apk`).  
4. Op de NUC: `git pull` + `./installeer.sh` (backend/web moeten ook mee).  
5. Op de tablet: banner **Installeren** → één keer bevestigen in het Android-scherm. Toestaan: “apps uit onbekende bronnen” voor Archie OS.

Bij een **ander subnet / nieuw VM-IP**: open de app → vul op login (of splash) het nieuwe `http://…:4000` in — geen nieuwe APK nodig.

Zonder APK-asset op de Release blijft alleen de server-banner zichtbaar; de tablet-app zelf verandert dan niet.

Check: `curl -s http://127.0.0.1:4000/api/version` → `latest.androidApk.available` moet `true` zijn.

### Zo publiceer jij een “nieuwe stand” (ontwikkelaar)

1. Merge / push naar GitHub.  
2. Maak een **Release** (of tag), bv. `v0.3.0` — semver, liefst met `v`.  
3. (Tablet) Upload de bijpassende APK als release-asset.  
4. Op elke NUC: `git pull` (of nieuwe ZIP) + `./installeer.sh`.  
5. Tot de NUC is bijgewerkt, zien browsers de server-banner; tablets met oude APK zien **Installeren** zodra de Release een APK heeft.

Check handmatig: `curl -s http://127.0.0.1:4000/api/version`

---

## Later: updaten op de NUC

```bash
cd ~/KNX-app
git pull          # of nieuwe ZIP uitpakken over de map (house.json niet wissen)
./installeer.sh
```

`config/house.json` en `docker/data/` blijven bewaard. `house.json` staat niet in git (elk huis is anders); `installeer.sh` bewaart een kopie in `docker/data/house.json.keep` en zet die terug als het bestand na een `git pull` ontbreekt.

---

## Problemen

| Symptoom | Wat doen |
|----------|----------|
| Script: “Docker ontbreekt” | Antwoord **J**, of herstart na Docker-install |
| Pagina niet bereikbaar | VM-IP / Proxmox-bridge / zelfde LAN |
| Geen GitHub-melding | Release/tag aangemaakt? Repo publiek of `GITHUB_TOKEN`? Internet vanaf VM? |
| **GitHub ophalen mislukt** | Repo public: geen token nodig. Op de NUC: `GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch origin`. Oude/verkeerde `GITHUB_TOKEN` of opgeslagen git-login geeft 401, ook op een public repo. |
| Tablet: geen **Installeren** | Release heeft `.apk`-asset? `latest.androidApk` in `/api/version`? App gebouwd met `--dart-define=APP_VERSION=…` (niet `dev`)? |
| Tablet: installatie geweigerd | “Onbekende apps installeren” toestaan voor Archie OS; zelfde signing als vorige APK |
| Leeg scherm / oude app | Tab sluiten of banner **Vernieuwen** |
| KNX werkt niet | Installer: gateway-IP, KNX aanzetten (leeg huis start met KNX uit) |

---

## Buitenshuis (Archie Cloud)

`installeer.sh` vraagt "Remote toegang via Archie Cloud inschakelen?". Met een
eenmalige code van de beheerder (zie `cloud/README.md`) krijgt de NUC een eigen
`https://<id>.archiecloud.nl` en houdt hij zelf een WireGuard-verbinding naar de
VPS open. Geen poorten op de router, geen VPN-app op de telefoon.

- De app kiest bij starten en bij terugkeren uit de achtergrond zelf tussen het
  LAN-adres (thuis, <200 ms) en de cloud-URL. De NUC geeft die URL in
  `/api/health` door, dus na één keer thuis inloggen staat hij op de telefoon.
- Camera en intercom lopen buitenshuis via de TURN-relay op de VPS
  (`/api/media/ice` levert tijdelijke credentials). Thuis blijft het direct.
- ETS op afstand: installateur krijgt een WireGuard-profiel; op de NUC
  `docker compose --profile knxd up -d` met `KNX_GATEWAY_HOST` in `.env`.

Later alsnog aanzetten: `cd docker && ./install.sh` opnieuw; de vraag komt
terug zolang `REMOTE_URL` in `.env` leeg is.

### Telefoon koppelen zonder wachtwoord

Instellingen → **Telefoon koppelen** toont een QR en een code (10 minuten,
eenmalig). Voor iemand die alleen een telefoon heeft: Gebruikers → persoon →
**Telefoon koppelen** en de link via sms/WhatsApp/mail sturen. De link is
`https://<huis>.archiecloud.nl/pair?code=…`: met de app geïnstalleerd opent
Android die direct (App Links, zie `cloud/README.md`), anders stuurt de
server door naar de web-app (`/#/pair?…`). De code kan ook getypt worden
("Ik heb een koppelcode"). De telefoon krijgt een refresh-token (1 jaar,
schuivend) en vernieuwt zelf op de achtergrond.

Gekoppelde apparaten staan onder Instellingen → Telefoon koppelen (eigen) en
per gebruiker in Gebruikers; daar kan een apparaat afgemeld worden. Een nieuw
wachtwoord of een verwijderde/uitgezette gebruiker meldt automatisch alle
apparaten van die gebruiker af (het eigen toestel van wie zijn wachtwoord
wijzigt blijft). Opslag: `docker/data/sessions.json`.

### Deurbel bij gesloten app (Android)

Werkt zodra de server aan Archie Cloud hangt en op de VPS Firebase is
ingesteld (`cloud/README.md`). De NUC stuurt een bel via de WireGuard-hub
naar de push-relay; de telefoon toont het native belscherm. Tokens staan in
`docker/data/push.json` en volgen de sessies: apparaat afgemeld = geen push.
Deurbel stil (per account) geldt ook voor push.

## Technisch (naslag)

| Pad op host | Inhoud |
|-------------|--------|
| `config/house.json` | Huis (devices) — blijft bij updates |
| `docker/data/` | Logs, locks, tokens, **Asterisk-config** (`asterisk/`) |
| `docker/go2rtc/` | Camera-stream config |
| `docker/.env` | Geheim + URL’s + GitHub — niet delen |

Compose draait **twee** services: `knx-stack` (app + API + go2rtc) en `asterisk` (SIP). Beide `network_mode: host`. SIP UDP **5060**, WSS **8089**, RTP 10000–10100.

- Health: `curl -s http://127.0.0.1:4000/api/health`
- Versie: `curl -s http://127.0.0.1:4000/api/version`
