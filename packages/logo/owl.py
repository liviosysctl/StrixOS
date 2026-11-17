"""The owl of the distro as SVG: frontal, wings spread, in a double ring.

    python3 owl.py ACCENT BACKGROUND > owl.svg

The owl and the ring are drawn in ACCENT, the engraved lines in BACKGROUND (the background it
is shown on), the eyes are always white with the pupils in ACCENT.
"""

import math
import sys

EYE = "#ffffff"


def mirror(x):
    return 1000 - x


def points(pts):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)


def both_sides():
    """The left half as drawn, the right one mirrored"""
    return (lambda x: x), mirror


def owl(fig, ink, pupil):
    out = []

    def line(d, width=2.4, color=ink):
        return (
            f'<path d="{d}" stroke="{color}" stroke-width="{width}" fill="none" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
        )

    # Wings: ten primaries fanning out, the coverts above them, rows of small feathers
    for f in both_sides():
        n = 10
        for k in range(n):
            t = k / (n - 1)
            tx, ty = 136 + t * (424 - 136), 470 + t * 24
            angle = math.radians(-13 * (1 - t) ** 1.2)
            length = 262 - 36 * t
            bx, by = tx + length * math.sin(angle), ty + length * math.cos(angle)
            w = 16
            out.append(
                f'<path d="M{f(tx - w):.1f} {ty:.1f} L{f(bx - w + 2):.1f} {by - 30:.1f} '
                f'Q{f(bx):.1f} {by + 14:.1f} {f(bx + w - 2):.1f} {by - 30:.1f} '
                f'L{f(tx + w):.1f} {ty:.1f} Z" fill="{fig}"/>'
            )
            out.append(line(f"M{f(tx):.1f} {ty + 4:.1f} L{f(bx):.1f} {by - 6:.1f}", 3))
            barbs = 13
            for j in range(1, barbs):
                s = j / barbs
                sx, sy = tx + (bx - tx) * s, ty + 4 + (by - 10 - ty) * s
                for side in (-1, 1):
                    out.append(
                        line(f"M{f(sx + side * 2.5):.1f} {sy:.1f} L{f(sx + side * 11):.1f} {sy + 9:.1f}", 1.5)
                    )
        coverts = [
            (450, 404), (396, 376), (320, 352), (240, 340), (176, 350), (130, 380),
            (108, 428), (112, 470), (136, 484), (300, 496), (432, 510), (454, 476),
        ]
        out.append(
            f'<polygon points="{points([(f(x), y) for x, y in coverts])}" fill="{fig}" '
            f'stroke="{fig}" stroke-width="8" stroke-linejoin="round"/>'
        )
        for row, (base, amp, x0, x1) in enumerate([(384, -28, 170, 420), (420, -22, 132, 430), (456, -8, 122, 432)]):
            count = int((x1 - x0) / 30) + 1
            for i in range(count):
                x = x0 + i * (x1 - x0) / (count - 1)
                u = (x - 150) / (430 - 150)
                y = base + amp * math.sin(math.pi * u) + (12 if x > 400 and row == 0 else 0)
                out.append(line(f"M{f(x - 14):.1f} {y - 7:.1f} Q{f(x):.1f} {y + 12:.1f} {f(x + 14):.1f} {y - 7:.1f}"))
                out.append(f'<circle cx="{f(x):.1f}" cy="{y - 1:.1f}" r="2.4" fill="{ink}"/>')
        for i in range(12):
            u = i / 11
            x, y = 128 + u * (432 - 128), 484 + u * 22
            out.append(f'<circle cx="{f(x):.1f}" cy="{y:.1f}" r="15" fill="{fig}"/>')
            out.append(line(f"M{f(x - 14):.1f} {y + 2:.1f} Q{f(x):.1f} {y + 22:.1f} {f(x + 14):.1f} {y + 2:.1f}"))
        out.append(line(f"M{f(150):.1f} 372 Q{f(290):.1f} 330 {f(436):.1f} 396", 2.2))

    # Body with scales
    left = [(500, 380), (450, 388), (426, 430), (418, 510), (422, 590), (436, 660), (462, 712), (500, 732)]
    body = left + [(mirror(x), y) for x, y in reversed(left[1:-1])]
    out.append(
        f'<clipPath id="body"><polygon points="{points(body)}"/></clipPath>'
        f'<polygon points="{points(body)}" fill="{fig}"/>'
    )
    scales = []
    for row, y in enumerate(range(420, 724, 24)):
        for x in range(404 + (12 if row % 2 else 0), 604, 24):
            scales.append(line(f"M{x - 11} {y - 6} Q{x} {y + 11} {x + 11} {y - 6}", 2.5))
            scales.append(f'<circle cx="{x}" cy="{y}" r="1.8" fill="{ink}"/>')
    out.append(f'<g clip-path="url(#body)">{"".join(scales)}</g>')

    # Legs and talons
    for f in both_sides():
        out.append(f'<path d="M{f(458)} 696 L{f(456)} 766 L{f(488)} 766 L{f(490)} 706 Z" fill="{fig}"/>')
        for y in range(712, 764, 9):
            out.append(line(f"M{f(460)} {y} L{f(473)} {y + 6} L{f(486)} {y}", 1.8))
        for ex, ey in [(424, 800), (462, 814), (500, 804)]:
            out.append(line(f"M{f(472)} 766 L{f(ex)} {ey}", 14, fig))
            out.append(line(f"M{f(ex)} {ey} Q{f(ex + (ex - 472) * 0.3)} {ey + 16} {f(ex - 3)} {ey + 24}", 5, fig))
            for q in (0.35, 0.6, 0.82):
                px, py = 472 + (ex - 472) * q, 766 + (ey - 766) * q
                out.append(line(f"M{f(px - 4):.1f} {py - 2:.1f} L{f(px + 4):.1f} {py + 2:.1f}", 1.8))

    # Head: a superellipse with ear tufts
    half = []
    for i in range(0, 181, 6):
        a = math.radians(90 + i)
        c, s = math.cos(a), math.sin(a)
        x = 500 + 158 * math.copysign(abs(c) ** (2 / 2.3), c)
        y = 292 - 120 * math.copysign(abs(s) ** (2 / 2.3), s)
        if y < 240:
            y -= 26 * math.exp(-((x - 382) ** 2) / 700)
        half.append((x, y))
    head = half + [(mirror(x), y) for x, y in reversed(half[1:-1])]
    out.append(
        f'<polygon points="{points(head)}" fill="{fig}" stroke="{fig}" stroke-width="6" stroke-linejoin="round"/>'
    )
    for x in range(400, 604, 16):
        if abs(x - 500) >= 20:
            out.append(line(f"M{x - 5} 190 L{x} 198 L{x + 5} 190", 1.8))

    # Eyes: white, a ring of fine lines, the pupil in the accent
    for f in both_sides():
        cx, cy = 432, 296
        out.append(f'<circle cx="{f(cx)}" cy="{cy}" r="74" fill="{EYE}" stroke="{ink}" stroke-width="3.4"/>')
        out.append(f'<circle cx="{f(cx)}" cy="{cy}" r="66" fill="none" stroke="{ink}" stroke-width="1.6"/>')
        for i in range(36):
            a = 2 * math.pi * i / 36
            x1, y1 = cx + 44 * math.cos(a), cy + 44 * math.sin(a)
            x2, y2 = cx + 62 * math.cos(a), cy + 62 * math.sin(a)
            out.append(line(f"M{f(x1):.1f} {y1:.1f} L{f(x2):.1f} {y2:.1f}", 2.6))
        out.append(f'<circle cx="{f(cx)}" cy="{cy}" r="38" fill="{ink}"/>')
        out.append(f'<circle cx="{f(cx)}" cy="{cy}" r="32" fill="{pupil}"/>')
        out.append(f'<circle cx="{f(cx + 10)}" cy="{cy - 11}" r="7" fill="{EYE}"/>')
        out.append(line(f"M{f(360)} 222 Q{f(440)} 196 {f(496)} 248", 3.6))
    out.append(f'<path d="M484 338 Q500 328 516 338 L500 374 Z" fill="{ink}"/>')
    return "".join(out)


def svg(accent, background):
    ring = (
        f'<circle cx="500" cy="500" r="484" fill="none" stroke="{accent}" stroke-width="12"/>'
        f'<circle cx="500" cy="500" r="456" fill="none" stroke="{accent}" stroke-width="4"/>'
    )
    # The owl a little smaller than the ring, so the talons and wing tips keep clear of it
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">'
        f'{ring}<g transform="translate(70 66) scale(0.86)">{owl(accent, background, accent)}</g></svg>\n'
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.stdout.write(svg(sys.argv[1], sys.argv[2]))
