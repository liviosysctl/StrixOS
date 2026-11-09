# Template for /etc/nixos

The installer copies these files to `/etc/nixos`. Placeholders:

- `@distroId@` and `@distroUrl@` are filled in by the build (`packages.machine-template`), so the name only lives in `branding.nix` and the update source only in `flake.nix`.
- The installer fills in every other `@...@` with the answers.

`hardware.nix` and `flake.lock` are not here: `nixos-generate-config` creates the first on the machine, the ISO build creates the second.
