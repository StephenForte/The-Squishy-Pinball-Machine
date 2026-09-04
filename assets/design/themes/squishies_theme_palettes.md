# Squishies Pinball — Theme Palette Direction

The supplied image establishes the baseline: deep indigo arcade darkness, glossy saturated candy objects, rounded forms, and small high-energy light accents.

## Recommended starting point

Use `neon_candy_baseline` for the first playable table. It is the closest match to the reference and gives the game a clear identity: purple/cyan rails, pink/yellow/orange interactables, and white score/UI elements.

## Palette selection

| Palette | Mood | Best use |
|---|---|---|
| Neon Candy Baseline | Bright neon arcade | Main/default table |
| Grape Jam | Dark, purple, premium | Night mode or advanced table |
| Aqua Pool | Cool, friendly, aquatic | Alternate table or bonus mode |
| Sherbet Sunrise | Warm, playful, dessert-like | Family-friendly alternate table |

## Godot implementation guidance

Treat the palette keys as semantic roles, not as fixed object assignments. For example, `object_pink` can color a bumper on one table and a ramp on another while preserving the same visual language.

```gdscript
var theme_colors = {
    "background": Color("#080B45"),
    "playfield_base": Color("#19145E"),
    "rail_primary": Color("#5635D6"),
    "rail_secondary": Color("#16CFE0"),
    "object_pink": Color("#FF5D73"),
    "object_yellow": Color("#FFD21C"),
    "object_orange": Color("#FF9E18"),
    "glow_magenta": Color("#FF2BD6"),
    "glow_gold": Color("#FFF06A"),
    "text_primary": Color("#FFFFFF")
}
```

For the “squishy” rendering feel, pair these colors with low-to-moderate roughness, soft specular highlights, subtle ambient occlusion, and a thin colored rim light. Keep bloom restrained; too much bloom will erase the shape definition that makes the candy forms readable.

The complete palettes and all hex values are in `squishies_theme_palettes.json`.

## 2D note (D-002)

The engine is 2D. Material/lighting guidance above is art direction, not engine settings — see `godot_notes.engine_2d_interpretation` in the JSON.
