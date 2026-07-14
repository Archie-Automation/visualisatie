# Scenes

Scenes group multiple KNX writes behind a single tap, so customers can
capture "moods" (Welkom Thuis, Lezen, Goede Nacht) and trigger them from
anywhere in the app. They are fully editable by the end-user – no ETS or
admin panel needed.

## Scope

Scenes live at two levels:

| Scope  | Stored at                   | Rendered on            |
| ------ | --------------------------- | ---------------------- |
| Global | `HouseConfig.scenes[]`      | Dashboard "SCENES"     |
| Room   | `Room.scenes[]` (per room)  | Top of the room screen |

Each room supports up to 8 scenes (UI typically shows 4 at a time with
horizontal scroll). The dashboard supports up to 32.

## Data model

```jsonc
{
  "id": "scn-welcome",
  "name": "Welkom Thuis",
  "icon": "door",          // optional, from kSceneIconPalette
  "color": "#B08A4E",      // optional accent hex
  "actions": [
    { "ga": "1/1/1", "role": "switch",   "value": true },
    { "ga": "1/2/1", "role": "dim_value", "value": 60, "delayMs": 120 },
    { "ga": "4/2/1", "role": "setpoint", "value": 21 }
  ]
}
```

### Roles and DPTs

| Role           | DPT       | Value type      |
| -------------- | --------- | --------------- |
| `switch`       | DPT1.001  | bool            |
| `bit`          | DPT1.001  | bool            |
| `dim_value`    | DPT5.001  | number 0–100    |
| `percent`      | DPT5.001  | number 0–100    |
| `position`     | DPT5.001  | number 0–100    |
| `byte`         | DPT5.010  | integer 0–255   |
| `setpoint`     | DPT9.001  | number °C       |
| `temperature`  | DPT9.001  | number °C       |
| `scene_number` | DPT17.001 | integer 0–63    |

### `delayMs`

Optional per-action delay (0…30 000 ms) applied **before** the telegram
fires. Useful to stagger heavy scenes so the gateway isn't hammered
within one event loop tick.

## API

All endpoints require a valid bearer token.

### `POST /api/scenes/:id/run`

Execute a scene (looks up by id in both global and room scope).
The room ACL of the caller is checked when the scene is room-scoped.

### `PUT /api/scenes`

Replace the full list of global scenes.

```json
{ "scenes": [ /* Scene[] */ ] }
```

Requires `canEditScenes` (admin is always allowed).

### `PUT /api/rooms/:roomId/scenes`

Replace the scene list of a specific room. Also requires the caller to
have visibility on that room.

## ACL

```jsonc
"access": { "editScenes": false }   // defaults to true
```

When `editScenes` is `false`, the user can still **run** scenes but the
"+" chip and the "long-press to edit" affordance disappear from the UI.
Admins bypass this check.

## Flutter UI

- `SceneStrip` — horizontal row of chips. Tap to run, long-press to
  edit. Trailing "+" opens the editor when editing is allowed.
- `SceneEditorSheet` — full-screen bottom sheet. Users can rename the
  scene, pick an icon, add/remove actions (GA + role + value) and save.
  Save calls the appropriate PUT endpoint and invalidates the config
  provider so the strip refreshes instantly.

## Editor workflow for customers

1. Dashboard or Room screen → tap the **+** chip in the SCENES row.
2. Editor sheet opens. A blank scene called "Nieuwe Scene" is created
   automatically.
3. Give it a name, pick an icon.
4. Tap **Toevoegen** to add an action: enter a GA (validated pattern
   `x/y/z`), pick the role (Schakelen, Dimmen, Setpoint, …) and a value.
5. Repeat for each telegram.
6. Tap **Opslaan**. The sheet closes, the config reloads, the new scene
   appears in the strip.

Long-press any existing chip to edit it again. A **Scene verwijderen**
button inside the editor deletes the currently-selected scene.
