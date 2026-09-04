# Squishies Pinball — Character Catalog

Version 2.0 reflects the current lineup: seven animals, one alien, and eight whimsical objects or fantasy characters.

The catalog is designed for a reusable `Squishy.tscn` scene. Each entry supplies a silhouette, semantic palette roles, material direction, gameplay role, behavior, scoring, and future asset paths.

Load it in Godot with:

```gdscript
var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/design/squishes/squishies_catalog.json"))
for squishy_data in catalog.squishies:
    print(squishy_data.display_name)
```

The `palette_roles` values refer to `squishies_theme_palettes.json`, allowing the characters to switch themes without changing their catalog data.

## Canonical paths (D-020)

- Catalog: `res://assets/design/squishes/squishies_catalog.json`
- Sprites: `res://assets/design/squishes/art/<id>.png` (generated from the sheet, see `sheet.keying`)
- Palettes: `res://assets/design/themes/squishies_theme_palettes.json`
