# Calling-card artist workflow

The pipeline prepares the scoreboard's separate background and detail layers.
The source also implements profile-scoped account unlocks, survivor selections
and den-trader purchases; their live and visual review remains open. The
scoreboard draws the defaults in a 125-pixel-high area whose width varies with
the UI, so a 6:1 source image can be stretched at other window sizes. An
in-game handcrafted/generated visual review is required before broad rollout.

## Artist inputs

Put original or otherwise cleared PNG artwork under
[`assets/scoreboard/callingcards`](../assets/scoreboard/callingcards) and edit
[`recipes.json`](../assets/scoreboard/callingcards/recipes.json). Nested
folders are allowed. The file classifies itself without a recipe entry:

| Artist file | Category | Stable ID | Staged material |
| --- | --- | --- | --- |
| `custom_background.png` | background | `background_custom` | `scoreboard/backgrounds/custom_background.png` |
| `custom_details.png` | detail | `detail_custom` | `scoreboard/details/custom_details.png` |

Finished PNGs must have a 6:1 aspect ratio, at any resolution. Their original
bytes and transparency are copied unchanged. The stem's derived display name
must be at most 120 characters. The stem may contain ASCII
letters, digits, spaces, hyphens and single underscores between words; IDs are
lowercase with separators normalized to underscores. Source directories do not
become part of the ID or staged filename, so conflicting names in different
folders fail rather than overwrite each other. `background_default` and
`detail_default` are reserved for the existing default images.

Other PNGs are ingredients only when referenced by a recipe. An unreferenced
PNG without a finished-card suffix is reported as an error; non-PNG files are
reported as ignored. Finished images can also be ingredients. Do not copy
mounted Valve content into the addon; check rights for every finished image
and ingredient before staging.

## Recipes

The following is an illustrative configuration, not supplied artwork. It
expects `patterns\fabric.png` and `symbols\star.png` in the artist-source
folder. JSON strings represent backslashes as `\\`:

```json
{
  "schemaVersion": 1,
  "aliases": {
    "background_old_blue": "background_blue"
  },
  "shopPrices": {
    "background_blue": 125,
    "background_red": 250
  },
  "questRewards": {
    "background_blue": true
  },
  "recipes": [
    {
      "category": "background",
      "layers": [
        { "image": "patterns\\fabric.png", "mode": "cover", "color": "primary" },
        {
          "image": "symbols\\star.png",
          "mode": "repeat",
          "color": "#ffffffaa",
          "opacity": 0.55,
          "scale": 0.5,
          "spacingX": 12,
          "spacingY": 8,
          "offsetX": 4,
          "offsetY": 2
        }
      ],
      "outputs": [
        {
          "id": "background_blue",
          "name": "Blue stars",
          "baseColor": "#101010ff",
          "colors": { "primary": "#264878" }
        },
        {
          "id": "background_red",
          "name": "Red stars",
          "baseColor": "#101010ff",
          "colors": { "primary": "#783026" }
        }
      ]
    }
  ]
}
```

`schemaVersion`, `aliases` and `recipes` are required. `shopPrices` and
`questRewards` are optional objects keyed by active non-default card IDs.
Each recipe has a
`category` of `background` or `detail`, a `layers` array and a nonempty
`outputs` array. The arrays are ordered: each layer is composited over the
preceding layers. An empty layer array is allowed.

Each output requires a unique lowercase `id` beginning with its category
(`background_` or `detail_`) and a nonempty display `name` of at most 120
characters without control characters. ID words contain ASCII letters or
digits separated by single underscores. Optional `baseColor` defaults to
transparent black; optional `colors` maps lowercase names to colours. Every
layer using a named colour must find that name in each output's `colors`.

Each layer requires a relative PNG `image` in the source folder and a `mode`:

- `cover` uniformly scales and centers the image to cover the 750x125
  canvas at the default scale of 1, cropping excess. Lower scales or offsets
  can leave part of the canvas uncovered.
- `repeat` tiles the scaled image across the canvas.

Optional layer controls:

| Field | Default | Meaning and bounds |
| --- | --- | --- |
| `color` | `#ffffffff` | A literal `#RRGGBB` / `#RRGGBBAA`, or a named output colour. It multiplies the image channels and alpha. |
| `opacity` | `1` | Additional alpha multiplier from 0 to 1. |
| `scale` | `1` | Image scale from 0.0001 to 4096. |
| `spacingX`, `spacingY` | `0` | Transparent pixel spacing for `repeat` only; whole numbers from 0 to 8192. |
| `offsetX`, `offsetY` | `0` | Pixel offset, right/down positive; each from -1000000 to 1000000. |

Colour alpha is the final two hex digits when present. Repeat tiles are also
limited to 8192 pixels on either axis and 16,777,216 pixels total. Generated
outputs are 750x125; their material names include their explicit IDs. Unsafe
or missing paths, unknown fields, duplicate IDs and material collisions fail
the whole build.

IDs stay the same when unrelated inputs or outputs are added or reordered.
For a deliberate rename, add an alias from the unused old ID to the new ID in
the same category. Alias chains must end at an active card; cycles and dangling
targets fail validation. When a selection is missing, the catalogue resolver
returns the relevant default without changing the saved ID.

## Acquisition and selection

The two built-in defaults are free. Every other finished or generated design
must have an acquisition source. An ID in `shopPrices` is sold by den traders
for the specified whole-number credit price from 1 to 1,000,000. Without an
explicit `questRewards` entry, an unpriced design defaults to quest-only and
a priced design defaults to shop-only. Set its quest flag to `true` to allow a
priced design through both routes; setting it to `false` without a shop price
is rejected. Unknown, removed or built-in IDs and non-boolean quest flags are
rejected. The example makes Blue stars available from both routes and Red
stars shop-only.

Unlocks are shared by the Steam account's survivors within a world profile;
each survivor chooses its own background and detail from the scoreboard.
The den trader charges the active survivor's credits. Unlocks never occupy a
backpack slot and cannot be resold. A removed design retains its saved ownership
and selection, showing the default until it returns or is explicitly aliased.

`ZM_CallingCardService:GrantReward(player, id, reason)` is a server-only API
for an active design marked `questReward = true`. It is not yet connected to a
quest system; calling cards are not loot drops. The installed catalogue contains
the two free defaults and five generated designs, each priced at five credits
and eligible for future quest rewards. The user deferred their in-game review.

## Plan, build and stage

Run these commands from the repository root in Windows PowerShell. Planning
validates inputs and prints every output without writing files:

```powershell
.\bin\build_calling_cards.ps1 -PlanOnly
```

The current first-review ceiling is **512 generated outputs total**; finished
cards and the two defaults do not count toward it. Exceeding the ceiling fails
the complete plan rather than dropping outputs. It is not a permanent cap or
a request to create 512 designs. Obtain separate approval before a larger or
otherwise expensive catalogue build.

After approval for the intended bounded preview, build and inspect the new
directory and its PNGs:

```powershell
$build = .\bin\build_calling_cards.ps1
$build.directory
```

Each build gets a unique directory under `generated\callingcards_preview`;
it does not stage content. A failed build removes its own incomplete preview
directory. Review a small handcrafted and generated example in the actual
scoreboard before broad rollout; offline PNG inspection is not in-game
acceptance.

Staging is a dry run unless `-Apply` is given:

```powershell
.\bin\stage_calling_cards.ps1 -BuildDirectory $build.directory
```

After explicit approval for that staging and confirmation that **all** source
art and ingredients may be distributed, apply the exact reviewed build:

```powershell
.\bin\stage_calling_cards.ps1 -BuildDirectory $build.directory -Apply -RightsConfirmed
```

`-RightsConfirmed` records the operator's confirmation; it does not establish
or independently verify a licence. The stager checks source, destination and
catalogue hashes, refuses to overwrite an unowned or modified file, and
publishes `content\data_static\calling_cards.json` last. The existing default
images must match the build and are not overwritten. Workshop packaging owns
the catalogue in core and scoreboard images in common and checks active
catalogue material hashes.

The catalogue records files owned by this pipeline. Removing a card from the
artist inputs removes it from the active catalogue but retains its previously
owned file; returning the same stable design can reuse that path. Manually
authored/unowned files are never pruned or replaced. Do not hand-edit the
generated catalogue or staged materials.

If staging raises a handled error, it attempts to restore every previous file
and the previous catalogue. If restoration is incomplete, the error names a
`.callingcards-stage-*` directory under `content\data_static` containing the
journal and backups. An interrupted process can also leave a transaction
directory. Stop further staging, preserve that directory and inspect the
journal and file hashes before recovering; do not delete or overwrite
unverified files.

## Focused checks

```powershell
.\tests\powershell\test_calling_cards.ps1
.\tests\powershell\test_workshop_packages.ps1
python -m unittest discover -s .\tests\phase_d -p 'test_*.py' -v
.\tests\powershell\test_glua_syntax.ps1
```

For a fresh preview client, `zn_test_calling_cards` runs isolated native server
storage and purchase cases and writes `data/zombiesim/calling_card_tests.json`.
`zombiesim_dev_test_calling_card_client` and
`zombiesim_dev_test_calling_card_ui` run mocked client fixtures and write
separate DATA reports. `zombiesim_dev_calling_card_materials` reports materials
the client has requested.

Fixtures do not verify actual rendered appearance, real-survivor interactions,
distribution rights or multiplayer behavior. Client fixture reports are not
proof that the real scoreboard or trader controls were exercised.
