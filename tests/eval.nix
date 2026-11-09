# Checks that only evaluate and build nothing big.
# Run with: nix flake check
{ self, pkgs }:


let
  inherit (pkgs) lib;
  branding = import ../branding.nix;
  configs = self.nixosConfigurations;
  iso = configs."${branding.id}-iso".config;
  reference = configs."${branding.id}-reference";

  # A check passes if this derivation can be evaluated at all.
  ok = name: pkgs.runCommand "check-${name}" { } "touch $out";

  # An expression that must fail. tryEval catches throw and assert,
  # so also NixOS assertions and the unfree check.
  mustFail =
    name: expr:
    assert !(builtins.tryEval (builtins.deepSeq expr expr)).success;
    ok name;

  # The reference machine with one extra module, as drvPath
  toplevelWith =
    module: (reference.extendModules { modules = [ module ]; }).config.system.build.toplevel.drvPath;

  withApps = file: toplevelWith { ${branding.id}.apps.file = lib.mkForce file; };
in
{
  # The ISO evaluates (it is not built here)
  eval-iso = builtins.seq iso.system.build.isoImage.drvPath (ok "eval-iso");

  # The installer functions, without disks, root or network
  installer-functions =
    pkgs.runCommand "check-installer-functions"
      {
        nativeBuildInputs = with pkgs; [ bash coreutils gawk gnugrep gnused jq util-linux ];
      }
      ''
        bash ${./installer.sh} \
          ${self.packages.${pkgs.stdenv.hostPlatform.system}.machine-template} \
          ${pkgs.callPackage ../installer/logo.nix { }} \
          ${../installer} | tee $out
      '';

  # Guest tools must never end up on the installer medium
  iso-clean =
    assert !iso.virtualisation.vmware.guest.enable;
    assert !iso.virtualisation.virtualbox.guest.enable;
    ok "iso-clean";

  # Both test machines go through mkSystem like a real installation
  eval-reference = builtins.seq reference.config.system.build.toplevel.drvPath (ok "eval-reference");
  eval-vmware = builtins.seq
    configs."${branding.id}-vmware".config.system.build.toplevel.drvPath
    (ok "eval-vmware");

  # Hibernation without a swap file must be refused
  storage-hibernation-needs-swap = mustFail "storage-hibernation-needs-swap" (toplevelWith {
    ${branding.id}.storage.swapSize = lib.mkForce null;
  });

  # A package that no longer exists: only a warning, the update goes on
  apps-unknown-is-warning = builtins.seq (withApps ./fixtures/apps-unknown.json) (
    ok "apps-unknown-is-warning"
  );

  # An unknown apps.json format is refused
  apps-wrong-version = mustFail "apps-wrong-version" (withApps ./fixtures/apps-v2.json);

  # Unfree packages only with the unfree field
  apps-unfree-with-field = builtins.seq (withApps ./fixtures/apps-unfree.json) (
    ok "apps-unfree-with-field"
  );
  apps-unfree-needs-field = mustFail "apps-unfree-needs-field" (
    withApps ./fixtures/apps-unfree-unmarked.json
  );
}
