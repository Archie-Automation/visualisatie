# Tijdschema's (Schedules)

Tijdschema's laten scenes of een groep apparaten automatisch uitvoeren op
een bepaald moment. Ze zijn bedoeld voor de eindklant: beheer ze direct
in de app via **Instellingen → Tijdschema's**. Onder water worden ze
opgeslagen in `config/house.json` onder de `schedules` array.

Er zijn twee soorten triggers: **tijd** en **astro**.

## Tijd-trigger

Draait op een vaste klok­tijd in de projectzone. Kies de dagen waarop
hij mag vuren.

```json
{
  "id": "sch-goodnight",
  "name": "Alles uit",
  "enabled": true,
  "trigger": {
    "kind": "time",
    "time": "23:30",
    "days": [true, true, true, true, true, false, false]
  },
  "action": { "kind": "scene", "sceneId": "scn-goodnight" }
}
```

`days` is een array van zeven booleans, **maandag eerst** (ISO).
`[true, true, true, true, true, false, false]` = doordeweeks.

## Astro-trigger (zonsopkomst / zonsondergang)

Op basis van de locatie (`project.location.lat/lon`) berekent de backend
dagelijks de exacte tijd van zonsop­komst of -ondergang. Een optionele
`offsetMin` schuift de trigger vooruit (negatief) of achteruit
(positief) in minuten.

```json
{
  "id": "sch-sunset-welcome",
  "name": "Welkom bij zonsondergang",
  "enabled": true,
  "trigger": {
    "kind": "astro",
    "event": "sunset",
    "offsetMin": -15,
    "days": [true, true, true, true, true, true, true],
    "notBefore": { "kind": "time", "time": "17:00" },
    "notAfter":  { "kind": "time", "time": "21:30" }
  },
  "action": { "kind": "scene", "sceneId": "scn-welcome" }
}
```

Range voor `offsetMin`: **-720…720** minuten (−12 u tot +12 u).

### Begrenzing: `notBefore` / `notAfter`

Gebruik dit om de astro-trigger binnen een venster te houden. Zonder
begrenzing zouden extreme zomers/winters de scene op gekke momenten
triggeren. `notBefore`/`notAfter` kan een **vaste tijd** (`kind: "time"`)
of **een andere astro-anker** (`kind: "astro"`) zijn — handig voor
"bij zonsondergang, maar niet voor zonsopkomst+30min".

* `notBefore` — trigger schuift op naar dit moment als de berekende
  astro-tijd eerder valt.
* `notAfter` — trigger wordt die dag overgeslagen als de berekende
  tijd later valt.

## Actie: scene of ad-hoc apparaatlijst

Twee vormen:

1. **Bestaande scene** — verwijs naar `sceneId`. De scene wordt op de
   trigger-tijd precies zo uitgevoerd als je hem zelf zou indrukken.
   ```json
   "action": { "kind": "scene", "sceneId": "scn-welcome" }
   ```
2. **Ad-hoc apparaatlijst** — stel rechtstreeks een lijstje apparaten in
   zonder eerst een scene aan te maken. In de app kies je apparaten via
   dezelfde picker als bij scenes; de app zet ze om in losse
   `SceneAction`s.
   ```json
   "action": {
     "kind": "actions",
     "actions": [
       { "ga": "1/1/1", "role": "switch", "value": true },
       { "ga": "1/2/1", "role": "dim_value", "value": 30 }
     ]
   }
   ```

## Achter de schermen

* `backend/src/scheduler.ts` berekent de eerstvolgende trigger per
  schedule en zet een `setTimeout`. Na het vuren wordt de volgende
  occurrence berekend.
* `suncalc` levert astro-tijden; de projectzone (`project.timezone`,
  default `"Europe/Amsterdam"`) stuurt de kalenderberekening zodat DST
  geen dubbele triggers geeft.
* Na elke fire wordt `lastRun` geüpdatet in `house.json`.
* `POST /api/schedules/:id/run` draait een schedule handmatig voor
  tests; `PUT /api/schedules` slaat de volledige lijst atomair op en
  reboot de scheduler.

## API endpoints

| Method | Path                          | Beschrijving                          |
| ------ | ----------------------------- | ------------------------------------- |
| GET    | `/api/schedules`              | Huidige lijst                         |
| PUT    | `/api/schedules`              | Volledige lijst opslaan (editScenes)  |
| POST   | `/api/schedules/:id/run`      | Nu uitvoeren (editScenes)             |

De `editScenes` ACL is dezelfde die scene-bewerking bepaalt — klanten
die scenes mogen maken kunnen ook tijdschema's beheren.
