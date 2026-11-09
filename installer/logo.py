"""Draw a name in a 5 x 5 pixel font, with a shadow one pixel down and right.

Usage: logo.py NAME > logo.txt

Output uses "#" for a letter pixel, "s" for a shadow pixel and "." for empty,
one character per pixel. The installer turns each pixel into two terminal
cells and picks the colors at runtime, depending on what the terminal can show.
"""

import sys

FONT = {
    "A": [".###.", "#...#", "#####", "#...#", "#...#"],
    "B": ["####.", "#...#", "####.", "#...#", "####."],
    "C": [".####", "#....", "#....", "#....", ".####"],
    "D": ["####.", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "####.", "#....", "#####"],
    "F": ["#####", "#....", "####.", "#....", "#...."],
    "G": [".####", "#....", "#..##", "#...#", ".####"],
    "H": ["#...#", "#...#", "#####", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "###..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "####.", "#....", "#...."],
    "Q": [".###.", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "####.", "#..#.", "#...#"],
    "S": [".####", "#....", ".###.", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
    "Z": ["#####", "...#.", "..#..", ".#...", "#####"],
    "0": [".###.", "#..##", "#.#.#", "##..#", ".###."],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["####.", "....#", ".###.", "#....", "#####"],
    "3": ["####.", "....#", ".###.", "....#", "####."],
    "4": ["#...#", "#...#", "#####", "....#", "....#"],
    "5": ["#####", "#....", "####.", "....#", "####."],
    "6": [".###.", "#....", "####.", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", "..#.."],
    "8": [".###.", "#...#", ".###.", "#...#", ".###."],
    "9": [".###.", "#...#", ".####", "....#", ".###."],
    "-": ["...", "...", "###", "...", "..."],
    " ": ["..", "..", "..", "..", ".."],
}

ROWS = 5


def letter_pixels(name):
    grid = [[] for _ in range(ROWS)]
    for index, char in enumerate(name.upper()):
        glyph = FONT[char]
        gap = [False] if index < len(name) - 1 else []
        for row in range(ROWS):
            grid[row] += [pixel == "#" for pixel in glyph[row]] + gap
    return grid


def with_shadow(grid):
    height, width = len(grid), len(grid[0])
    lines = []
    for row in range(height + 1):
        line = ""
        for col in range(width + 1):
            letter = row < height and col < width and grid[row][col]
            shadow = 0 < row <= height and 0 < col <= width and grid[row - 1][col - 1]
            line += "#" if letter else "s" if shadow else "."
        lines.append(line.rstrip("."))
    return lines


def main():
    name = sys.argv[1]
    unknown = sorted({char for char in name.upper() if char not in FONT})
    if unknown:
        sys.exit(f"logo.py: no glyph for {' '.join(unknown)}")
    print("\n".join(with_shadow(letter_pixels(name))))


if __name__ == "__main__":
    main()
