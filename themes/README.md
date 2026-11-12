# Themes

The themes of Strix are the eight Roman gods of the design system [StrixUI](https://github.com/liviosysctl/StrixUI). They come in as the flake input `strixui` (`design-system/themes/<id>/theme.toml`), so a new version of StrixUI reaches every machine with the weekly update. The theme engine (`packages/theme-engine`) reads them, checks them while the system is built, and applies the chosen one at runtime. More themes come from theme repositories, see below.

`default.nix` names the theme a new installation starts with: `saturnus`. The installer on the ISO and the boot splash use it too.

| Theme | Variant | Look |
|---|---|---|
| `saturnus` | `dark` | Strix red. Saturn, lord of time and of the night hours; the default |
| `janus` | `dark` | Patina, the green of old bronze doors and keys |
| `apollo` | `dark` | Antique gold, worn brass |
| `mars` | `dark` | Rust, iron and burnt sienna |
| `vulcanus` | `dark` | Olive, the patina on old bronze from the forge |
| `neptunus` | `dark` | Deep water, slate and ink blue |
| `pluto` | `dark` | Heather, faded plum |
| `bacchus` | `dark` | Claret, old wine |

`strix-theme list` shows each with its name and description. To change a god theme, change it in StrixUI (`tools/themes.py`, then `tools/build.py`).

## Switching

```sh
strix-theme list                 # themes and variants, the current one marked with *
strix-theme current              # e.g. janus:dark
strix-theme show janus:dark      # all colors of a variant as JSON
sudo strix-theme set janus       # the default variant of janus
sudo strix-theme set janus:dark
strix-theme status               # whether every part shows the current theme
```

The command carries the distro's id (`strix-theme`). Tab completes the commands and, after `set` and `show`, every theme and variant, also behind `sudo`. bash does it out of the box, zsh and fish once they are enabled (`programs.zsh.enable`, `programs.fish.enable`). `strix-theme list --names` prints the same list for scripts.

The desktop session shows its own theme on top of the machine's: every 10 minutes another god, unless the theme is kept in the theme picker (Super Ctrl Space, then K). That change stays in the session (`$XDG_RUNTIME_DIR/strix/theme`) and never touches the stored choice, the EFI variable or the boot splash. A theme chosen in the picker is the machine's choice, as `set`; polkit lets the active local session do that without a password. `strix-theme session call state` shows the session's side.

`set` works at once, without a rebuild:

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
name = "Janus"                  # shown to people, at most 40 characters
description = "Patina, the green of old bronze doors and keys."
default-variant = "dark"        # used for "janus" without a variant

[variants.dark]
name = "Dark"
appearance = "dark"             # "light" or "dark"

[variants.dark.colors]
background = "#070c09"
# ... the ten required colors, then any extra colors

[variants.dark.terminal]
background = "#070c09"
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

Every other key under `colors` is an extra color. Extra colors are passed on unchanged in `tokens.json`. The gods use them to carry every token of StrixUI under its own name (`accent-soft`, `border-active`, ...).

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

## Theme repositories

Anyone can make themes for Strix: a theme repository is a Git repository with a fixed layout (layout 1). Start from [strix-theme-template](https://github.com/liviosysctl/strix-theme-template); [strix-theme-lucifer](https://github.com/liviosysctl/strix-theme-lucifer) is the first one.

```
strix-themes.toml          # layout = 1, name, description, author
themes/<id>/theme.toml     # this format
themes/<id>/wallpaper.jpg  # JPEG, 2560 by 1440, at most 4 MiB
themes/<id>/wallpaper.toml # caption, credit, licence ("public domain" or "CC0")
```

```sh
sudo strix-theme repos add someone/strix-theme-x   # owner/repo means GitHub; else an https:// address
sudo strix-rebuild switch                          # builds its themes in
strix-theme repos list                             # address, commit, themes, last problem
sudo strix-update --themes                         # fetch them all now and switch
sudo strix-update --themes Lucifer                 # only one, by name or address
sudo strix-theme repos remove Lucifer && sudo strix-rebuild switch
strix-theme repos check ./my-checkout              # for theme authors: the same rules on a checkout
```

`repos add` and `repos update` fetch the newest commit of the default branch (HTTPS only, one commit, no submodules, no LFS, at most 50 MiB) and check it: the layout, exactly the three files per theme and nothing else, the wallpaper, the licence, this format, and that no id is a god's or another repository's. Only a commit that passes is taken. Its themes are copied into `/etc/nixos/themes/<id>/` and the commit is written into `/etc/nixos/themes.json`. A repository whose newest commit fails keeps the one it has, and `repos list` says why.

`strix-update` does this for every repository before it fetches the new release, and rebuilds when either changed. A theme repository never stops an update. The rebuild reads only the copies in `/etc/nixos`, so it needs no network for them, and a repository that disappears from the net keeps its themes. `lib.mkSystem` finds `themes.json` beside `apps.json`, so machines installed before it existed need no change.

Connected themes appear in `strix-theme list` after the gods and switch like them. Their wallpaper travels in `tokens.json` as the theme folder (`dir`), the QML module of StrixUI shows it.

## Adding a theme without a repository

1. Make a folder `<id>/` with a `theme.toml`. Copy a god's `theme.toml` from StrixUI as a start.
2. Check it: `strix-theme check <folder with the theme folder>`.
3. Add it in `machine.nix`:

   ```nix
   strix.theme.extraThemes.my-theme = ./my-theme;   # a folder next to machine.nix
   strix.theme.default = "my-theme";                # optional: start with it
   ```

   Then `sudo strix-rebuild switch` and `sudo strix-theme set my-theme`.

## Not in format 1 yet

Fonts, radii, spacing and motion. They are the same for every theme and live in the design system (`packages/ui`). Wallpapers are not in `theme.toml` either: the gods' are in StrixUI, a theme repository's sit next to its `theme.toml`. New optional keys keep `format = 1`; a change that breaks existing themes raises the number, and the engine refuses formats it does not know.
