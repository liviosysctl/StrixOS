# Themes

Every folder here is a theme. The folder name is the theme's id, the folder holds a `theme.toml`. The theme engine (`packages/theme-engine`) reads them, checks them while the system is built, and applies the chosen one at runtime.

`default.nix` names the theme a new installation starts with.

| Theme | Variants | Look |
|---|---|---|
| `neutral` | `dark` | Plain black and red. The installer, the boot splash and the documents. |
| `chamber` | `light` (Lights on), `dark` (Lights off) | The design system Chamber UI: white cards with black sign plates. |

## Switching

```sh
strix-theme list                 # themes and variants, the current one marked with *
strix-theme current              # e.g. chamber:dark
strix-theme show chamber:dark    # all colors of a variant as JSON
sudo strix-theme set chamber     # the default variant of chamber
sudo strix-theme set chamber:dark
strix-theme status               # whether every part shows the current theme
```

The command carries the distro's id (`strix-theme`). `set` works at once, without a rebuild:

| Part | When |
|---|---|
| `/run/strix/theme/tokens.json` for programs that read the colors directly (Quickshell) | right away |
| Palette of the virtual consoles | right away |
| Plymouth splash at shutdown and reboot | right away |
| Plymouth splash at boot | from the next boot |

The choice is stored in `/var/lib/strix/theme/selection`. At every boot the `strix-theme` service applies it again. If the stored theme no longer exists, the default is used and `status` says so.

The boot splash runs in the initrd, before the root file system is there. `set` therefore also writes the theme into an EFI variable (`Theme-595702b9-5e56-4cc8-9b1a-d145cfd71953`), and a unit in the initrd reads it before Plymouth starts. The initrd holds the splash of every variant. Nothing in the initrd can fail the boot: on any problem the default splash stays.

## The format

```toml
format = 1                      # the format this file is written in
name = "Chamber"                # shown to people, at most 40 characters
description = "White cards with black sign plates, like a test chamber."
default-variant = "light"       # used for "chamber" without a variant

[variants.light]
name = "Lights on"
appearance = "light"            # "light" or "dark"

[variants.light.colors]
background = "#f2f3f5"
# ... the ten required colors, then any extra colors

[variants.light.terminal]
background = "#2a2d32"
# ... foreground, cursor, selection and the 16 terminal colors
```

Ids of themes and variants: lowercase letters, digits and single hyphens, starting with a letter, at most 32 characters. Colors are `#rrggbb`, extra colors may also be `#rrggbbaa`. Short forms like `#fff` are not accepted, so every value is exact. Unknown keys are errors, so a typo does not go unnoticed.

### Required colors

| Name | Use | Rule |
|---|---|---|
| `background` | Desktop, behind everything; the boot splash | |
| `surface` | Cards, bars, windows, dialogs | |
| `border` | Lines and frames on `surface` | |
| `text` | Text on `background` and `surface`; the wordmark of the splash | 4.5:1 on both |
| `text-muted` | Secondary text | 4.5:1 on `surface` |
| `accent` | The one highlight: main action, running progress, the installer's color | |
| `on-accent` | Text on `accent` | 4.5:1 on `accent` |
| `focus` | Focus rings | 3:1 on `background` and `surface` |
| `error` | Error text | 4.5:1 on `surface` |
| `warning` | Warnings, as a fill | |

The contrast rules follow WCAG 2.x: 4.5:1 for text, 3:1 for parts of the interface. `appearance` must match the colors: a dark variant has text lighter than its background.

Every other key under `colors` is an extra color. Extra colors are passed on unchanged in `tokens.json`. Chamber uses them to carry every token of its design system under its own name (`sign`, `on-sign`, `wall-panel`, ...).

### Terminal colors

`background`, `foreground`, `cursor`, `selection` and the 16 ANSI colors `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white` and their `bright-` forms. `foreground` needs 4.5:1 on `background`.

The virtual consoles take the 16 colors, with two changes: color 0 becomes `background` and color 7 becomes `foreground`, because the console draws its text in color 7 on color 0.

## What follows the theme

| Part | Reads | Where |
|---|---|---|
| Quickshell and other programs | `tokens.json`: every color, the terminal colors, `appearance`, the theme folder | at runtime |
| Virtual consoles | the 16 terminal colors | at runtime |
| Plymouth | `background`, `text`, `accent`; one Plymouth theme per variant | built per variant, picked at boot |
| Console installer on the ISO | `accent`, `text-muted`, terminal colors | built from the default theme |

## Adding a theme

1. Make a folder `themes/<id>/` with a `theme.toml`. Copy `neutral/theme.toml` as a start.
2. Check it: `nix build .#themes -L`. The build fails with a list of every problem.
3. To use it right away on one machine without changing the repository, add it in `machine.nix`:

   ```nix
   strix.theme.extraThemes.my-theme = ./my-theme;   # a folder next to machine.nix
   strix.theme.default = "my-theme";                # optional: start with it
   ```

   Then `sudo strix-rebuild switch` and `sudo strix-theme set my-theme`.

## Not in format 1 yet

Fonts, radii, spacing and motion, wallpapers and other assets. They come with the desktop. New optional keys keep `format = 1`; a change that breaks existing themes raises the number, and the engine refuses formats it does not know.
