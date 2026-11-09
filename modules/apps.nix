# Apps from the Store. The Store only writes /etc/nixos/apps.json,
# this module turns it into packages.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.apps;

  data =
    if cfg.file == null then
      { version = 1; packages = [ ]; }
    else
      lib.importJSON cfg.file;

  # A package that no longer exists in nixpkgs does not break the update,
  # it only warns. The Store can then show it as "no longer available".
  lookup =
    entry:
    let
      path = lib.splitString "." entry.attr;
    in
    if lib.hasAttrByPath path pkgs then
      [ (lib.getAttrFromPath path pkgs) ]
    else
      lib.warn "apps.json: ${entry.attr} no longer exists in nixpkgs" [ ];

  # From the JSON file, not from pkgs: pkgs depends on nixpkgs.config,
  # looking into pkgs here would be an infinite recursion.
  unfreeNames = map (entry: entry.unfree) (lib.filter (entry: entry ? unfree) data.packages);
in
{
  options.${branding.id}.apps.file = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "apps.json from /etc/nixos.";
  };

  config = {
    assertions = [
      {
        assertion = (data.version or 0) == 1;
        message = "apps.json has format ${toString (data.version or "?")}, this ${branding.name} only knows format 1.";
      }
    ];

    environment.systemPackages = lib.optionals ((data.version or 0) == 1) (
      lib.concatMap lookup data.packages
    );

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeNames;
  };
}
