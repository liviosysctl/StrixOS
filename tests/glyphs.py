"""Check that a console font has every character of some text files.

Usage: glyphs.py FONT.psf[.gz] FILE...

Prints each missing character with the file it comes from and exits 1 if
there is one. Reads PSF1 and PSF2 fonts with a Unicode table, like the ones
in kbd and terminus_font.
"""

import gzip
import struct
import sys


def font_chars(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as file:
        data = file.read()
    chars = set()
    if data[:2] == b"\x36\x04":
        mode, size = data[2], data[3]
        count = 512 if mode & 1 else 256
        table = data[4 + count * size :]
        for (value,) in struct.iter_unpack("<H", table[: len(table) // 2 * 2]):
            if value not in (0xFFFF, 0xFFFE):
                chars.add(chr(value))
    else:
        _, _, offset, _, count, size, _, _ = struct.unpack("<8I", data[:32])
        table = data[offset + count * size :]
        chars = set(table.decode("utf-8", "replace")) - {"�"}
    return chars


def main():
    font, files = sys.argv[1], sys.argv[2:]
    have = font_chars(font)
    missing = False
    for name in files:
        with open(name, encoding="utf-8") as file:
            text = file.read()
        for char in sorted({c for c in text if ord(c) > 126} - have):
            print(f"{name}: {char} (U+{ord(char):04X}) is not in the font")
            missing = True
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
