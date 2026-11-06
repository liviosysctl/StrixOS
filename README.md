# Strix

Strix is a NixOS-based Linux distribution for people coming from Windows. The goal is NixOS without the terminal: create the install stick on Windows with one click, install apps from a store with one click, and switch the look of the whole desktop with a theme.

This is an early work in progress. Nothing here builds a usable system yet.

## What is in the repository

| Path | Content |
|---|---|
| `branding.nix` | The only place the distro name appears. Everything else derives from it. |
| `modules/storage/btrfs.nix` | Disk layout with disko: GPT, ESP, optional LUKS, btrfs with flat subvolumes, Snapper for `/home`. |
| `modules/os-release.nix` | Name and version in `/etc/os-release`, shared by the ISO and installed systems. |
| `iso/default.nix` | The installer ISO, built on the minimal NixOS installer. |
| `installer/` | `strix-install`, for now a placeholder. |
| `tests/eval.nix` | Checks for `nix flake check`, e.g. no VM guest tools in the ISO. |
| `flake.nix` | Version, modules, the ISO, checks and a dev shell. |

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

## Development

```sh
nix develop
```

The dev shell activates the commit hook. Commit and release rules are in [CONTRIBUTING.md](CONTRIBUTING.md).
