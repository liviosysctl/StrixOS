# Vorlage für /etc/nixos

Der Installer kopiert diese Dateien nach `/etc/nixos`. Platzhalter:

- `@distroId@` ersetzt der Build (`packages.machine-template`), damit der Name nur in `branding.nix` steht.
- Alle anderen `@...@` füllt der Installer mit den Antworten aus.

`hardware.nix` und `flake.lock` sind nicht hier: Die erste erzeugt `nixos-generate-config` auf der Maschine, die zweite der ISO-Build.
