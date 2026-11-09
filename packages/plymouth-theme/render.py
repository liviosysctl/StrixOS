"""Generate a Plymouth theme from theme data.

Usage: render.py <out> <id> <name> <font> <background> <foreground> <accent> <script.in>
Writes the wordmark as PNG (Inter ExtraBold), a 1x1 accent color and
the finished script with the colors filled in.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

out, theme_id, name, font_path, background, foreground, accent, script_in = sys.argv[1:]
out = Path(out)
out.mkdir(parents=True)


def rgb(hex_color):
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def plymouth_floats(hex_color):
    return [f"{channel / 255:.4f}" for channel in rgb(hex_color)]


# Render the wordmark large, Plymouth scales it to the screen height
font = ImageFont.truetype(font_path, 400)
font.set_variation_by_name("ExtraBold")
left, top, right, bottom = font.getbbox(name)
wordmark = Image.new("RGBA", (right - left, bottom - top), (0, 0, 0, 0))
ImageDraw.Draw(wordmark).text((-left, -top), name, font=font, fill=rgb(foreground) + (255,))
wordmark.save(out / "wordmark.png")

Image.new("RGBA", (1, 1), rgb(accent) + (255,)).save(out / "accent.png")

values = {
    "BG": plymouth_floats(background),
    "FG": plymouth_floats(foreground),
}
script = Path(script_in).read_text()
for key, (r, g, b) in values.items():
    script = script.replace(f"@{key}_R@", r).replace(f"@{key}_G@", g).replace(f"@{key}_B@", b)
(out / f"{theme_id}.script").write_text(script)

(out / f"{theme_id}.plymouth").write_text(
    f"""[Plymouth Theme]
Name={name}
Description={name} boot splash
ModuleName=script

[script]
ImageDir={out}
ScriptFile={out}/{theme_id}.script
"""
)
