# GUI art assets

## Board texture

- File: `board/wood_light.jpg`
- Source asset: **Wood 017** by ambientCG
- Source: https://ambientcg.com/view?id=Wood017
- License: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
- Original file: `Wood017_1K-JPG_Color.jpg` (1024 x 1024)
- Local changes: renamed only

This is a seamless, light yellow-brown wood color texture suitable for the
surface of a 2D Go board. The material's displacement, normal, and roughness
maps are not included because the current desktop GUI only needs the color map.

## Glossy Go stones

- Files: `stones/black.png`, `stones/white.png`
- Source asset: **Go stones** by zpmorgan
- Source: https://opengameart.org/content/go-stones
- Renderer source: https://github.com/zpmorgan/gostones-render
- License: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
- Original files: `b.png` and `w.png`
  (300 x 300, transparent background)
- Local changes: renamed only

## Matte Go stones

- Files: `stones/black_matte.png`, `stones/white_matte.png`
- Source: generated specifically for this project with OpenAI image generation
- Original files: 1254 x 1254 PNG on a solid chroma-key background
- Local changes: chroma-key background removed, alpha edges softened and
  despilled, visible stone diameters normalized, and canvases resized to
  1024 x 1024

The matte pair uses matching soft upper-left lighting. The white stone is a
plain warm-white material without shell grain, veins, or nacre patterns.


## UI icons

- File: `ui/board_lock.png`
- Source: generated specifically for this project with OpenAI image generation
- Local changes: chroma-key background removed, alpha edges softened and
  despilled, content centered, and canvas resized to 256 x 256

The icon combines overlapping black and white stones with a closed padlock.
The ambientCG board and zpmorgan stone assets are released under CC0 and can
be used, modified, and redistributed, including in commercial projects,
without attribution.
