# Apps aus dem Store. Der Store schreibt nur /etc/nixos/apps.json,
# dieses Modul macht daraus Pakete.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.apps;

  data =
    if cfg.file == null then
      { version = 1; packages = [ ]; }
    else
      lib.importJSON cfg.file;

  # Ein Paket, das es in nixpkgs nicht mehr gibt, bricht das Update nicht ab,
  # sondern gibt eine Warnung aus. Der Store kann es dann als "nicht mehr verfügbar" zeigen.
  lookup =
    entry:
    let
      path = lib.splitString "." entry.attr;
    in
    if lib.hasAttrByPath path pkgs then
      [ (lib.getAttrFromPath path pkgs) ]
    else
      lib.warn "apps.json: ${entry.attr} gibt es in nixpkgs nicht mehr" [ ];

  # Aus der JSON-Datei, nicht aus pkgs: pkgs hängt von nixpkgs.config ab,
  # ein Blick in pkgs hier wäre eine Endlosschleife.
  unfreeNames = map (entry: entry.unfree) (lib.filter (entry: entry ? unfree) data.packages);
in
{
  options.${branding.id}.apps.file = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "apps.json aus /etc/nixos.";
  };

  config = {
    assertions = [
      {
        assertion = (data.version or 0) == 1;
        message = "apps.json hat Format ${toString (data.version or "?")}, dieses ${branding.name} kennt nur 1.";
      }
    ];

    environment.systemPackages = lib.optionals ((data.version or 0) == 1) (
      lib.concatMap lookup data.packages
    );

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeNames;
  };
}
