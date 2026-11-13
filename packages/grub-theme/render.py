"""Draws a GRUB theme for one theme variant in the look of StrixUI: the god's wallpaper, darkened towards the
left like the lock screen, the wordmark in fraktur with the motto, and a boot menu of quiet rows where the
chosen one is raised and marked with an accent bar.

    render.py OUT TOKENS.json WALLPAPER|- NAME MOTTO FRAKTUR.ttf SERIF-ITALIC.ttf MONO.ttf FONT-NAME

Writes OUT/background.png, the pieces of the menu box and the selection, and OUT/theme.txt. The fonts GRUB
draws itself (.pf2) are made next to it by default.nix.
"""
import json, os, sys

from PIL import Image, ImageDraw, ImageFont

out, tokens_file, wallpaper, name, motto, fraktur, serif, mono, font_name = sys.argv[1:10]
os.makedirs(out, exist_ok=True)
c = json.load(open(tokens_file))['colors']

W, H = 1920, 1080
# The column on the left: where the wordmark, the menu and the hints stand, in pixels of the 1920 by 1080 picture
X = 150
COL = 640


def rgb(hex_):
    h = hex_.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgba(hex_, alpha):
    return rgb(hex_) + (round(alpha * 255),)


# ---------------------------------------------------------------- background

if wallpaper != '-':
    img = Image.open(wallpaper).convert('RGB')
    scale = max(W / img.width, H / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left, top = (img.width - W) // 2, (img.height - H) // 2
    img = img.crop((left, top, left + W, top + H))
else:
    img = Image.new('RGB', (W, H), rgb(c['background']))

# The background colour over the picture: almost solid behind the column, thinning out to the right,
# so the menu reads like the lock screen and the god still shows
row = Image.new('RGBA', (W, 1))
bg = rgb(c['background'])
for x in range(W):
    t = min(1.0, max(0.0, (x - COL - X) / (W * 0.55)))
    row.putpixel((x, 0), bg + (round(255 * (0.94 - 0.62 * (t * t * (3 - 2 * t)))),))
img = Image.alpha_composite(img.convert('RGBA'), row.resize((W, H)))

d = ImageDraw.Draw(img)

word = ImageFont.truetype(fraktur, 168)
try:
    word.set_variation_by_axes([300])
except Exception:
    pass
d.text((X - 6, 120), name, font=word, fill=rgb(c['text']))

italic = ImageFont.truetype(serif, 30)
d.text((X, 330), motto, font=italic, fill=rgb(c['text-muted']))

# The rule of StrixUI: a hair line with a short piece in the accent at its start
d.rectangle((X, 392, X + COL, 392), fill=rgb(c['border-strong']))
d.rectangle((X, 391, X + 56, 393), fill=rgb(c['accent']))

# The keys, quiet, at the foot of the column
small = ImageFont.truetype(mono, 17)
keys = [('Enter', 'start'), ('E', 'edit'), ('C', 'console')]
x = X
for key, what in keys:
    d.text((x, H - 120), key, font=small, fill=rgb(c['text']))
    x += d.textlength(key + ' ', font=small)
    d.text((x, H - 120), what, font=small, fill=rgb(c['text-faint']))
    x += d.textlength(what + '    ', font=small)

# PNG, not JPEG: the GRUB of the ISO is built without the jpeg module
img.convert('RGB').save(os.path.join(out, 'background.png'), optimize=True)


# ---------------------------------------------------------------- pieces of the boxes (GRUB draws them as nine pieces)

def pieces(prefix, fill, border, corner=4):
    """A box with a 1px border and rounded corners, cut into GRUB's nine pieces."""
    size = corner * 2 + 1
    box = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    if border:
        bd.rounded_rectangle((0, 0, size - 1, size - 1), radius=corner, fill=border)
        bd.rounded_rectangle((1, 1, size - 2, size - 2), radius=max(0, corner - 1), fill=fill)
    else:
        bd.rounded_rectangle((0, 0, size - 1, size - 1), radius=corner, fill=fill)
    k = corner
    parts = {
        'nw': (0, 0, k, k), 'n': (k, 0, k + 1, k), 'ne': (k + 1, 0, size, k),
        'w': (0, k, k, k + 1), 'c': (k, k, k + 1, k + 1), 'e': (k + 1, k, size, k + 1),
        'sw': (0, k + 1, k, size), 's': (k, k + 1, k + 1, size), 'se': (k + 1, k + 1, size, size),
    }
    for part, cut in parts.items():
        box.crop(cut).save(os.path.join(out, '%s_%s.png' % (prefix, part)))


pieces('menu', rgba(c['surface'], 0.88), rgba(c['border'], 1))
# The chosen row: raised, with a 3px bar in the accent on its left edge
raised, mark = rgba(c['surface-raised'], 1), rgba(c['accent'], 1)
for part, (w, colour) in {'nw': (3, mark), 'w': (3, mark), 'sw': (3, mark), 'n': (1, raised), 'c': (1, raised),
                          's': (1, raised), 'ne': (1, raised), 'e': (1, raised), 'se': (1, raised)}.items():
    Image.new('RGBA', (w, 1), colour).save(os.path.join(out, 'select_%s.png' % part))
pieces('term', rgba(c['surface-sunken'], 0.96), rgba(c['border'], 1))

# ---------------------------------------------------------------- theme.txt

menu_top = 440
menu_h = 6 * 40 + 24
theme = f'''# The boot menu of {name} in the colours of {json.load(open(tokens_file)).get("name", "")}, made by packages/grub-theme. Do not edit.
title-text: ""
desktop-image: "background.png"
desktop-color: "{c['background']}"
terminal-font: "{font_name} 16"
terminal-box: "term_*.png"
terminal-left: "{X}"
terminal-top: "{menu_top}"
terminal-width: "1200"
terminal-height: "520"
terminal-border: "0"

+ boot_menu {{
  left = {X}
  top = {menu_top}
  width = {COL}
  height = {menu_h}
  menu_pixmap_style = "menu_*.png"
  item_font = "{font_name} 16"
  item_color = "{c['text-muted']}"
  selected_item_font = "{font_name} 16"
  selected_item_color = "{c['text']}"
  selected_item_pixmap_style = "select_*.png"
  icon_width = 0
  icon_height = 0
  item_icon_space = 14
  item_height = 40
  item_padding = 12
  item_spacing = 0
  scrollbar = false
}}

+ label {{
  id = "__timeout__"
  left = {X}
  top = {menu_top + menu_h + 18}
  width = {COL}
  height = 24
  align = "left"
  font = "{font_name} 14"
  color = "{c['text-faint']}"
  text = "Starting in %d s, any key stops"
}}
'''
open(os.path.join(out, 'theme.txt'), 'w').write(theme)
