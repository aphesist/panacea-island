#!/usr/bin/env python3
# Draws the island apps' launcher icons: the house tile (black, a hairline edge) with a white
# Phosphor glyph. Needs fontTools (e.g. a venv: python -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools).
#   make-icons.py   -> writes icons/panacea-<name>.svg next to this file
# panacea-calculator.svg is drawn by hand and isn't touched.
import json, os, re, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICONS = {            # file name -> Phosphor glyph (fill style)
    "tasks": "pulse",
    "editor": "note-pencil",
    "files": "folder-simple",
    "updates": "package",
    "logs": "scroll",
    "screen": "aperture",
    "settings": "gear-six",
    "viewer": "image",
}
js = open(os.path.join(ROOT, "hypr/custom/ui/PkIcons.js")).read()
cmap_names = json.loads(re.search(r"var map = (\{.*?\});", js, re.S).group(1))
font = TTFont(os.environ.get("PH_FONT", os.path.expanduser("~/.local/share/fonts/phosphor/Phosphor-Fill.ttf")))
cmap, gs, upm = font.getBestCmap(), font.getGlyphSet(), font["head"].unitsPerEm
SIZE, GLYPH = 128, 64                     # tile 120 inside 128; glyph box 64
for name, glyph in ICONS.items():
    g = cmap[cmap_names[glyph]]
    s = GLYPH / upm
    off = (SIZE - GLYPH) / 2
    asc = font["hhea"].ascent                 # Phosphor's em box runs from the ascent down, upm tall
    pen = SVGPathPen(gs)
    gs[g].draw(TransformPen(pen, (s, 0, 0, -s, off, off + asc * s)))
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <rect x="4" y="4" width="120" height="120" rx="28" fill="#0a0a0a"/>
  <rect x="4.5" y="4.5" width="119" height="119" rx="27.5" fill="none" stroke="#ffffff" stroke-opacity="0.14"/>
  <path d="{pen.getCommands()}" fill="#ffffff"/>
</svg>
'''
    open(os.path.join(HERE, f"panacea-{name}.svg"), "w").write(svg)
    print("wrote", f"panacea-{name}.svg")
