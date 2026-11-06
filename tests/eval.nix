# Prüfungen, die nur auswerten und nichts Grosses bauen.
# Läuft mit: nix flake check
{ self, pkgs }:

let
  branding = import ../branding.nix;
  iso = self.nixosConfigurations."${branding.id}-iso".config;

  # Eine Prüfung besteht, wenn diese Ableitung überhaupt ausgewertet werden kann.
  ok = name: pkgs.runCommand "check-${name}" { } "touch $out";
in
{
  # Das ISO lässt sich auswerten (gebaut wird es hier nicht)
  eval-iso = builtins.seq iso.system.build.isoImage.drvPath (ok "eval-iso");

  # Gast-Tools dürfen nie im Installationsmedium landen
  iso-clean =
    assert !iso.virtualisation.vmware.guest.enable;
    assert !iso.virtualisation.virtualbox.guest.enable;
    ok "iso-clean";
}
