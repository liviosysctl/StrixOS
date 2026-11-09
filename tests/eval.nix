# Prüfungen, die nur auswerten und nichts Grosses bauen.
# Läuft mit: nix flake check
{ self, pkgs }:

let
  inherit (pkgs) lib;
  branding = import ../branding.nix;
  configs = self.nixosConfigurations;
  iso = configs."${branding.id}-iso".config;
  reference = configs."${branding.id}-reference";

  # Eine Prüfung besteht, wenn diese Ableitung überhaupt ausgewertet werden kann.
  ok = name: pkgs.runCommand "check-${name}" { } "touch $out";

  # Ein Ausdruck, der scheitern muss. tryEval fängt throw und assert,
  # also auch NixOS-Assertions und die Unfree-Sperre.
  mustFail =
    name: expr:
    assert !(builtins.tryEval (builtins.deepSeq expr expr)).success;
    ok name;

  # Die Referenzmaschine mit einem zusätzlichen Modul, als drvPath
  toplevelWith =
    module: (reference.extendModules { modules = [ module ]; }).config.system.build.toplevel.drvPath;

  withApps = file: toplevelWith { ${branding.id}.apps.file = lib.mkForce file; };
in
{
  # Das ISO lässt sich auswerten (gebaut wird es hier nicht)
  eval-iso = builtins.seq iso.system.build.isoImage.drvPath (ok "eval-iso");

  # Gast-Tools dürfen nie im Installationsmedium landen
  iso-clean =
    assert !iso.virtualisation.vmware.guest.enable;
    assert !iso.virtualisation.virtualbox.guest.enable;
    ok "iso-clean";

  # Beide Testmaschinen gehen den Weg über mkSystem wie eine echte Installation
  eval-reference = builtins.seq reference.config.system.build.toplevel.drvPath (ok "eval-reference");
  eval-vmware = builtins.seq
    configs."${branding.id}-vmware".config.system.build.toplevel.drvPath
    (ok "eval-vmware");

  # Ruhezustand ohne Swapfile muss abgelehnt werden
  storage-hibernation-needs-swap = mustFail "storage-hibernation-needs-swap" (toplevelWith {
    ${branding.id}.storage.swapSize = lib.mkForce null;
  });

  # Ein Paket, das es nicht mehr gibt: nur eine Warnung, das Update läuft weiter
  apps-unknown-is-warning = builtins.seq (withApps ./fixtures/apps-unknown.json) (
    ok "apps-unknown-is-warning"
  );

  # Ein unbekanntes Format von apps.json wird abgelehnt
  apps-wrong-version = mustFail "apps-wrong-version" (withApps ./fixtures/apps-v2.json);

  # Unfreie Pakete nur mit dem unfree-Feld
  apps-unfree-with-field = builtins.seq (withApps ./fixtures/apps-unfree.json) (
    ok "apps-unfree-with-field"
  );
  apps-unfree-needs-field = mustFail "apps-unfree-needs-field" (
    withApps ./fixtures/apps-unfree-unmarked.json
  );
}
