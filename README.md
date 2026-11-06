# Strix

Strix is a NixOS-based Linux distribution for people coming from Windows. The goal is NixOS without the terminal: create the install stick on Windows with one click, install apps from a store with one click, and switch the look of the whole desktop with a theme.

This is an early work in progress. Nothing here builds a usable system yet.

## What is in the repository

| Path | Content |
|---|---|
| `branding.nix` | The only place the distro name appears. Everything else derives from it. |
| `modules/storage/btrfs.nix` | Disk layout with disko: GPT, ESP, optional LUKS, btrfs with flat subvolumes, Snapper for `/home`. |
| `flake.nix` | Exposes the modules and a dev shell. |

## Planned

- Strix base system with Hyprland and Quickshell
- Theme engine: switch themes at runtime without a rebuild
- Store: install packages from nixpkgs with one click
- Bootstick app for Windows (separate repository)

## Development

```sh
nix develop
```

The dev shell activates the commit hook. Commit and release rules are in [CONTRIBUTING.md](CONTRIBUTING.md).
