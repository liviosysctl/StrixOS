# Strix

Strix is a NixOS-based Linux distribution for people coming from Windows. The goal is NixOS without the terminal: create the install stick on Windows with one click, install apps from a store with one click, and switch the look of the whole desktop with a theme.

This is an early work in progress. Nothing here builds a usable system yet.

## Branches

| Branch | Content |
|---|---|
| `main` | The proof of concept for the school module M245: Windows bootstick app, app store, signed ISO. |
| `personal` | The distribution as I use it myself, without the store and the beginner parts. |

Changes that matter for both go into both branches. When M245 is over, `personal` becomes `main` and the proof of concept moves to its own branch.

## What is in the repository

| Path | Content |
|---|---|
| `branding.nix` | The only place the distro name appears. Everything else derives from it. |
| `lib/mk-system.nix` | `lib.mkSystem`: builds a machine from the files in `/etc/nixos`. |
| `modules/` | The distro modules: os-release, base system, the three tools, apps from `apps.json`, disk layout. |
| `modules/storage/btrfs.nix` | Disk layout with disko: GPT, ESP, optional LUKS, btrfs with flat subvolumes, Snapper for `/home`, hibernation. |
| `modules/boot-splash.nix` | Graphical boot with Plymouth: wordmark, progress line, a styled passphrase field. |
| `packages/plymouth-theme/` | Builds the Plymouth theme from theme data. |
| `themes/` | Theme data. For now only the neutral base theme in black and red. |
| `templates/machine/` | Template for `/etc/nixos` that the installer fills in. |
| `hosts/` | Made-up machines for CI and testing: `reference` and `vmware`. |
| `iso/default.nix` | The installer ISO, built on the minimal NixOS installer. |
| `installer/` | `strix-install`: asks a few questions in the console, then partitions, encrypts and installs. `--core --answers FILE` installs without asking. |
| `tests/` | Checks for `nix flake check`. |
| `flake.nix` | Version, modules, machines, the ISO, checks and a dev shell. |

## On an installed machine

`/etc/nixos` holds `flake.nix`, `flake.lock`, `hardware.nix`, `machine.nix` and `apps.json`. Three commands work with it:

| Command | Does |
|---|---|
| `sudo strix-rebuild [switch\|boot\|test\|build]` | Rebuilds from `/etc/nixos` |
| `sudo strix-update` | Fetches the newest release and switches to it, keeps the old version if the build fails |
| `sudo strix-apps add\|remove <package>`, `strix-apps list` | Installs or removes a package from nixpkgs. This is what the Store calls. |

## Planned

- Strix base system with Hyprland and Quickshell
- Theme engine: switch themes at runtime without a rebuild
- Store: install packages from nixpkgs with one click
- Bootstick app for Windows (separate repository)

## Building the ISO

Needs Nix with flakes on Linux (NixOS-WSL works) and about 20 GB of free disk.

```sh
nix build .#iso-dev -L    # faster compression, for testing
nix build .#iso -L        # release compression
ls -lh result/iso/
```

The ISO boots on UEFI with Secure Boot off. Write it to a USB stick as a raw image, not by copying files onto a FAT32 stick.

Commit and push before building a release ISO. Only an ISO from a clean tree with a `flake.lock` pins the installed system to its own commit; from a dirty tree the installer locks during the install and needs the network for it.

## Installing

Boot the ISO, then:

```sh
sudo strix-install
```

It asks for the language first, and every screen after that is in German, French, Italian or English. Then keyboard, time zone, name, user, password, computer name, disk, encryption and hibernation, a summary, and it only starts after you type the disk's name. The whole disk is used. The log ends up in `/var/log/strix-install.log` on the installed system.

## Development

```sh
nix develop
```

The dev shell activates the commit hook. Commit and release rules are in [CONTRIBUTING.md](CONTRIBUTING.md).
