# Device types

An overview of every device type supported by the Archie OS backend,
with the KNX roles it speaks and the UI widget that renders it.

## Core types

| Type           | Flutter widget      | Commands                                   |
| -------------- | ------------------- | ------------------------------------------ |
| `light_switch` | `LightSwitchTile`   | `light.switch`                             |
| `light_dimmer` | `LightDimmerTile`   | `light.switch`, `light.dim`                |
| `shading`      | `ShadingTile`       | `shading.move`, `shading.position`, `shading.slats` |
| `climate`      | `ClimateTile`       | `climate.setpoint`                         |
| `media_sonos`  | placeholder (tbd)   | –                                          |
| `camera`       | `CameraTile`        | view only (HLS/WebRTC/snapshot)            |
| `intercom`     | `IntercomTile`      | WebRTC talk-back, `POST /release`          |

## Window coverings (`shading`)

One device type, seven visual variants. The `subtype` field controls the
icon + descriptive label, and whether a second "lamellen" slider is
rendered on top of the position slider.

| Subtype     | Icon                    | Position slider | Slats slider        |
| ----------- | ----------------------- | --------------- | ------------------- |
| `blind`     | `blinds_outlined`       | yes             | only if `ga.slat`   |
| `roller`    | `roller_shades_outlined`| yes             | no                  |
| `curtain`   | `curtains_outlined`     | yes (horizontal)  | no                  |
| `jalousie`  | `blinds_closed_outlined`| yes             | yes (needs `ga.slat`) |
| `screen`    | `vertical_shades_outlined` | yes (vertical) | no               |
| `sheers`    | `curtains`              | yes (horizontal)  | no                  |
| `awning`    | `deck_outlined`         | yes (vertical)  | no                  |

```jsonc
{
  "id": "dev-living-blinds",
  "type": "shading",
  "name": "Jaloezie Zuid",
  "subtype": "jalousie",
  "slider": true,
  "ga": {
    "up_down": "3/1/1",
    "stop_step": "3/2/1",
    "position": "3/3/1", "position_status": "3/4/1",
    "slat":     "3/5/1", "slat_status":     "3/6/1"
  }
}
```

- `slider: true` (default for shading) → continuous position slider with
  small ↑/stop/↓ pills underneath. `slider: false` → classic up/stop/down
  round buttons only.
- Slats slider appears automatically when `ga.slat` is set, and always
  for `subtype: "jalousie"`.
- Commands: `shading.move` (`up`|`down`|`stop`), `shading.position`
  (0–100 %), `shading.slats` (0–100 % lamellenstand).

## Comfort / extras

### `fireplace`

Represents a fireplace controller (e.g. Mertik Maxitrol, gas modulating
valve + electronic ignition) exposed on KNX.

```jsonc
{
  "id": "dev-living-fireplace",
  "type": "fireplace",
  "name": "Openhaard",
  "fireplace": {
    "onOff":   { "ga": "6/1/1", "statusGa": "6/1/2" },
    "flame":   { "ga": "6/2/1", "statusGa": "6/2/2", "steps": 5 },
    "safetyLockout": { "ga": "6/3/1" }
  }
}
```

- Default UI: 0–100 % slider for flame height (DPT5.001).
- Add `flame.steps` (2–10) for a discrete step bar (1..N) using DPT5.010
  bytes – useful for controllers that only accept presets.
- `safetyLockout` is read-only in the UI for now.

Commands: `fireplace.on`, `fireplace.flame`.

Tip: pair with a `confirm.on` prompt (see below) so guests can't
accidentally ignite the fireplace.

### `ac`

Split-unit air conditioning with setpoint, mode and fan speed.

```jsonc
{
  "id": "dev-master-ac",
  "type": "ac",
  "name": "Airco",
  "ac": {
    "onOff":     { "ga": "8/1/1", "statusGa": "8/1/2" },
    "setpoint":  { "ga": "8/2/1", "statusGa": "8/2/2", "min": 16, "max": 30 },
    "actualTemp":{ "ga": "8/3/1" },
    "mode": {
      "ga": "8/4/1", "statusGa": "8/4/2",
      "options": [
        { "label": "Auto",       "value": 0 },
        { "label": "Koelen",     "value": 1 },
        { "label": "Verwarmen",  "value": 2 },
        { "label": "Ventileren", "value": 3 },
        { "label": "Drogen",     "value": 4 }
      ]
    },
    "fanSpeed": {
      "ga": "8/5/1", "statusGa": "8/5/2",
      "options": [ { "label": "Auto", "value": 0 }, { "label": "1", "value": 1 } ]
    }
  }
}
```

Commands: `ac.on`, `ac.setpoint`, `ac.mode`, `ac.fanSpeed`.

### `fan`

Ventilator / ceiling fan / extractor hood.

```jsonc
{
  "id": "dev-kitchen-hood",
  "type": "fan",
  "name": "Afzuigkap",
  "fan": {
    "onOff": { "ga": "7/1/1", "statusGa": "7/1/2" },
    "speed": { "ga": "7/2/1", "statusGa": "7/2/2", "steps": 4 },
    "oscillate": { "ga": "7/3/1", "statusGa": "7/3/2" },
    "direction": { "ga": "7/4/1", "statusGa": "7/4/2" }
  }
}
```

- `speed.steps` → step bar (0..N, zero means off).
- Without `steps` → 0..100 % slider.
- `oscillate` / `direction` render as toggle chips.

Commands: `fan.on`, `fan.speed`, `fan.oscillate`, `fan.direction`.

### `universal`

A fully user-definable button panel. Ideal for boiler on/off, alarm
arming, custom presets, etc. Each button writes a single telegram on
tap; optional `actionOff` + `statusGa` makes a toggle.

```jsonc
{
  "id": "dev-hall-universal",
  "type": "universal",
  "name": "Scenes & Extra",
  "universal": {
    "columns": 2,
    "buttons": [
      {
        "id": "btn-all-off",
        "label": "Alles Uit",
        "icon": "power",
        "style": "danger",
        "action": { "ga": "0/0/1", "role": "bit", "value": true }
      },
      {
        "id": "btn-away",
        "label": "Afwezig",
        "icon": "travel",
        "statusGa": "0/0/2",
        "action":    { "ga": "0/0/2", "role": "bit", "value": true },
        "actionOff": { "ga": "0/0/2", "role": "bit", "value": false }
      },
      {
        "id": "btn-bell-volume",
        "label": "Deurbel Zacht",
        "icon": "volume",
        "style": "brass",
        "action": { "ga": "5/10/1", "role": "byte", "value": 20 }
      }
    ]
  }
}
```

#### Roles

| Role          | Value             | DPT          |
| ------------- | ----------------- | ------------ |
| `bit`         | bool              | DPT1.001     |
| `byte`        | integer 0–255     | DPT5.010     |
| `percent`     | number 0–100      | DPT5.001     |
| `temperature` | number °C         | DPT9.001     |
| `raw_int`     | integer 0–255     | DPT5.010     |

#### Styles

- `neutral` (default) – light surface, black text.
- `primary` – inverted ink button, brass highlight when active.
- `brass` – brass accent, switches to solid brass when active.
- `danger` – red accent, solid red when active.

When a button has a `statusGa` (and optional `statusOnValue`, defaults
to `true`/1) the tile renders an active "on" state reflecting the
current bus value.

Command: `universal.press` with `deviceId` and `buttonId`. The server
figures out which action (main or `actionOff`) to fire based on the
current status value.

## Confirm prompts ("weet je het zeker?")

Any device can opt-in to a confirmation dialog before its command
actually fires. The UI shows a small modal and only sends the command
when the user taps **DOORGAAN**. Useful for fireplaces, the front-door
intercom, "alles uit"-knoppen, etc.

Place a `confirm` object on the device:

```jsonc
{
  "id": "dev-living-fireplace",
  "type": "fireplace",
  "name": "Openhaard",
  "confirm": {
    "on": {
      "title": "Weet u zeker dat u de haard aan wilt zetten?",
      "message": "Let op: volg bij het gebruik van de haard altijd de veiligheids- en bedieningsvoorschriften van de fabrikant."
    }
  },
  "fireplace": { /* ... */ }
}
```

Fields:

| Field      | Fires before                                            |
| ---------- | ------------------------------------------------------- |
| `on`       | Turning the device on (fireplace / AC / fan / switch).  |
| `off`      | Turning the device off.                                 |
| `actions`  | Map `actionId → prompt`. For `intercom` the action key is `"release"` (door open); for `universal` it's the button `id`. |

The value of each prompt slot may be:

- `true` → default copy ("Weet je zeker dat je wilt doorgaan?");
- a string → shorthand for `{ message: "..." }`;
- an object `{ title?, message? }` for full control.

Examples:

```jsonc
// Door release on the voordeur intercom
"confirm": { "actions": { "release": "Voordeur openen?" } }

// Universal "alles uit" button
"confirm": { "actions": { "btn-all-off": "Alles in huis uitschakelen?" } }

// Symmetric confirm on a big outdoor floodlight switch
"confirm": { "on": true, "off": "Lichten in de tuin uitzetten?" }
```

The backend is only a carrier for this config – it returns `confirm`
alongside the device and the Flutter app shows the dialog. So no extra
backend roundtrip is needed to opt-in or out per device.

## Adding a new device type

1. Extend `DeviceType` in both `backend/src/types.ts` and
   `app/lib/src/models.dart`.
2. Add a schema definition to `config/house.schema.json`.
3. Add commands to `backend/src/commands.ts` (zod union + dispatch).
4. Teach `collectAllGAs` (in `backend/src/config.ts`) about the new
   group addresses so they're bound to the KNX bus.
5. Update `ROLE_DPT` in `backend/src/knxBus.ts` if new roles are needed.
6. Create a Flutter widget and wire it up in `deviceWidget()`.

Keep the `raw` JSON on the Dart `Device` model — the extra device types
read directly from `device.raw` so adding new fields never forces a
model-breaking migration.
