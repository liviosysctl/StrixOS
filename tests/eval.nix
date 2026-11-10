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
        nativeBuildInputs = with pkgs; [ bash coreutils gawk gnugrep gnused jq python3 util-linux ];
      }
      ''
        bash ${./installer.sh} \
          ${self.packages.${pkgs.stdenv.hostPlatform.system}.machine-template} \
          ${pkgs.callPackage ../installer/logo.nix { }} \
          ${../installer} \
          ${./glyphs.py} \
          ${pkgs.terminus_font}/share/consolefonts/${iso.console.font}.psf.gz | tee $out
      '';

  # Guest tools must never end up on the installer medium
  iso-clean =
    assert !iso.virtualisation.vmware.guest.enable;
    assert !iso.virtualisation.virtualbox.guest.enable;
    ok "iso-clean";

  # SSH is on, with a password but never for root. On the live system it runs
  # too (nixpkgs installer profile), logging in needs a password set with passwd.
  ssh-on =
    let
      cfg = reference.config.services.openssh;
    in
    assert cfg.enable;
    assert cfg.openFirewall;
    assert cfg.settings.PermitRootLogin == "no";
    assert cfg.settings.PasswordAuthentication;
    assert iso.services.openssh.enable;
    ok "ssh-on";

  # Over SSH from Ghostty or kitty, TERM must be known on both systems
  terminfo-ghostty-kitty =
    let
      has =
        cfg: name:
        lib.any (
          p: (p.outputName or "") == "terminfo" && lib.hasPrefix name (p.name or "")
        ) cfg.environment.systemPackages;
    in
    assert has reference.config "ghostty";
    assert has reference.config "kitty";
    assert has iso "ghostty";
    assert has iso "kitty";
    ok "terminfo-ghostty-kitty";

  # systemd tools print no emoji, also under sudo
  no-emoji =
    let
      off =
        cfg:
        (cfg.environment.variables.SYSTEMD_EMOJI or null) == "0"
        && lib.hasInfix ''env_keep += "SYSTEMD_EMOJI"'' cfg.security.sudo.extraConfig;
    in
    assert off reference.config;
    assert off iso;
    ok "no-emoji";

  # hostnamectl is wrapped (its chassis emoji ignores SYSTEMD_EMOJI), and
  # localed can find the keymap, so localectl shows it
  systemd-tools =
    let
      fixed =
        cfg:
        lib.any (p: lib.getName p == "hostnamectl") cfg.environment.systemPackages
        && cfg.systemd.services.systemd-localed.environment ? SYSTEMD_KEYMAP_DIRECTORIES;
    in
    assert fixed reference.config;
    assert fixed iso;
    ok "systemd-tools";

  # Every theme in themes/ passes the engine's check, and the engine's own
  # tests pass (they run while it is built)
  themes = (import ../lib/themes.nix { inherit pkgs; }).dir;

  # The splash follows the theme: one Plymouth theme per variant, the default
  # one set, the initrd unit that picks the stored one, /etc pointing at /run
  theme-splash =
    let
      cfg = reference.config;
      names = map (p: p.name) cfg.boot.plymouth.themePackages;
      unit = "${branding.id}-theme-boot";
    in
    assert cfg.boot.plymouth.theme == "${branding.id}-neutral-dark";
    assert lib.all (name: lib.elem name names) [
      "${branding.id}-neutral-dark"
      "${branding.id}-chamber-light"
      "${branding.id}-chamber-dark"
    ];
    assert cfg.boot.initrd.systemd.services ? ${unit};
    assert lib.elem "plymouth-start.service" cfg.boot.initrd.systemd.services.${unit}.before;
    assert cfg.environment.etc."plymouth/plymouthd.conf".source == "/run/${branding.id}/theme/plymouthd.conf";
    assert cfg.systemd.services."${branding.id}-theme".environment ? EFI_VARIABLE;
    ok "theme-splash";

  # Tab completion of the theme command in bash, zsh and fish, and bash finds it
  theme-completion =
    assert lib.elem "/share/bash-completion" reference.config.environment.pathsToLink;
    pkgs.runCommand "check-theme-completion"
      {
        nativeBuildInputs = with pkgs; [ bash coreutils zsh fish ];
      }
      ''
        export HOME=$TMPDIR
        bash ${./completion.sh} ${reference.config.${branding.id}.theme.package} ${branding.id}-theme | tee $out
      '';

  # Another default theme changes the splash, its default variant is used
  theme-default =
    let
      with' = default: (reference.extendModules { modules = [ { ${branding.id}.theme.default = default; } ]; }).config;
    in
    assert (with' "chamber").boot.plymouth.theme == "${branding.id}-chamber-light";
    assert (with' "chamber:dark").boot.plymouth.theme == "${branding.id}-chamber-dark";
    ok "theme-default";

  # A default theme that does not exist stops the build
  theme-default-unknown = mustFail "theme-default-unknown" (toplevelWith { ${branding.id}.theme.default = "nope"; });
  theme-default-unknown-variant = mustFail "theme-default-unknown-variant" (
    toplevelWith { ${branding.id}.theme.default = "chamber:dusk"; }
  );

  # The ISO: console colors and the command, but no splash and so no EFI variable
  theme-iso =
    let
      service = iso.systemd.services."${branding.id}-theme";
    in
    assert service.wantedBy == [ "multi-user.target" ];
    assert !(service.environment ? EFI_VARIABLE);
    assert !(iso.boot.initrd.systemd.services ? "${branding.id}-theme-boot");
    assert lib.elem iso.${branding.id}.theme.package iso.environment.systemPackages;
    ok "theme-iso";

  # Both test machines go through mkSystem like a real installation
  eval-reference = builtins.seq reference.config.system.build.toplevel.drvPath (ok "eval-reference");
  eval-vmware = builtins.seq
    configs."${branding.id}-vmware".config.system.build.toplevel.drvPath
    (ok "eval-vmware");

  # VMware guests unload VMCI around hibernation, other machines don't have the unit
  vmware-hibernate =
    let
      unit = "${branding.id}-vmware-hibernate";
      vmware = configs."${branding.id}-vmware".config.systemd.services;
    in
    assert vmware ? ${unit};
    assert lib.elem "vmware.service" vmware.${unit}.conflicts;
    assert lib.elem "hibernate.target" vmware.${unit}.wantedBy;
    assert !(reference.config.systemd.services ? ${unit});
    ok "vmware-hibernate";

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
