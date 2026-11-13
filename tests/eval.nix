# Checks that only evaluate and build nothing big.
# Run with: nix flake check
{ self, pkgs }:


let
  inherit (pkgs) lib;
  branding = import ../branding.nix;
  configs = self.nixosConfigurations;
  iso = configs."${branding.id}-iso".config;
  reference = configs."${branding.id}-reference";
  gods = [ "apollo" "bacchus" "janus" "mars" "neptunus" "pluto" "saturnus" "vulcanus" ];

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

  # Every god theme of StrixUI passes the engine's check, and the engine's own
  # tests pass (they run while it is built), the theme repositories' included
  themes =
    (import ../lib/themes.nix {
      inherit pkgs;
      builtin = "${self.inputs.strixui}/design-system/themes";
    }).dir;

  # The design system on the machine, and its QML module loads in Quickshell:
  # every component of the gallery, Strix.Shell, the theme from the engine's
  # tokens. Any QML warning or error fails the check.
  ui =
    let
      cfg = reference.config;
      ui = cfg.${branding.id}.ui.package;
      themes = cfg.system.build.themes;
      engine = lib.getExe cfg.${branding.id}.theme.package;
    in
    assert lib.elem ui cfg.fonts.packages;
    assert lib.hasSuffix "/qml" cfg.environment.sessionVariables.QML_IMPORT_PATH;
    pkgs.runCommand "check-ui"
      {
        nativeBuildInputs = [ pkgs.quickshell pkgs.gnugrep ];
      }
      ''
        export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/run QT_QPA_PLATFORM=offscreen
        mkdir -p -m 0700 $XDG_RUNTIME_DIR
        THEMES_DIR=${themes} ${engine} show janus > tokens.json
        cp ${./ui-load.qml} shell.qml
        TOKENS=$PWD/tokens.json GALLERY=file://${ui}/share/${branding.id}-ui/qml/gallery.qml \
          QML_IMPORT_PATH=${ui}/share/${branding.id}-ui/qml \
          timeout 60 quickshell -p $PWD/shell.qml > log.txt 2>&1 || true
        cat log.txt
        grep -q "STRIX-RESULT gallery=1 theme=janus" log.txt
        if grep -E "ERROR|WARN.*qml|\.qml:[0-9]+" log.txt; then
          echo "QML problems, see above"
          exit 1
        fi
        echo ok > $out
      '';

  # The desktop: the Hyprland configuration of the reference machine, every part
  # checked by Hyprland itself (--verify-config), with the colors the engine writes for a god;
  # the session, the login and the theme follower are there
  desktop =
    let
      check =
        name: cfg:
        let
          hypr = cfg.${branding.id}.desktop.hyprlandConfig;
          themes = cfg.system.build.themes;
          engine = lib.getExe cfg.${branding.id}.theme.package;
        in
        ''
          mkdir ${name}
          cp -L ${hypr}/hyprland.lua ${hypr}/machine.lua ${hypr}/bindings.lua ${hypr}/theme.lua ${name}/
          # theme.lua reads the session's colors, which the session service writes
          mkdir -p $XDG_RUNTIME_DIR/${branding.id}/theme
          THEMES_DIR=${themes} ${engine} render hyprland janus > $XDG_RUNTIME_DIR/${branding.id}/theme/hyprland.lua
          for part in machine theme bindings hyprland; do
            log=$(Hyprland --verify-config -c $PWD/${name}/$part.lua 2>&1) || { echo "$log"; echo "FAIL ${name} $part.lua"; exit 1; }
            echo "$log" | grep -q "config ok" || { echo "$log"; echo "FAIL ${name} $part.lua"; exit 1; }
            echo "ok   ${name} $part.lua"
          done
        '';
      reference' = reference.config;
    in
    assert reference'.programs.hyprland.withUWSM;
    assert reference'.${branding.id}.desktop.greeter == "strix";
    assert reference'.environment.sessionVariables.HYPRLAND_CONFIG == "/etc/xdg/${branding.id}/hypr/hyprland.lua";
    assert reference'.systemd.user.services ? "${branding.id}-theme-session";
    assert lib.hasInfix "org.freedesktop.policykit.exec" reference'.security.polkit.extraConfig;
    # The laptop: power profiles, Bluetooth off until asked, the lid suspends unless docked
    assert reference'.services.power-profiles-daemon.enable;
    assert reference'.hardware.bluetooth.enable;
    assert !reference'.hardware.bluetooth.powerOnBoot;
    assert reference'.${branding.id}.desktop.lid == "suspend";
    assert reference'.services.logind.settings.Login.HandleLidSwitch == "suspend";
    assert reference'.services.logind.settings.Login.HandleLidSwitchDocked == "ignore";
    assert reference'.environment.etc."xdg/${branding.id}/lid".text == "suspend\n";
    # GTK apps take the god's colors
    assert reference'.systemd.user.services ? "${branding.id}-gtk-colors";
    assert lib.any (p: lib.getName p == "adw-gtk3") reference'.environment.systemPackages;
    pkgs.runCommand "check-desktop"
      {
        nativeBuildInputs = [ reference'.programs.hyprland.package pkgs.gnugrep ];
      }
      ''
        export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/run
        mkdir -p -m 0700 $XDG_RUNTIME_DIR
        ${check "reference" reference'}
        test "$(grep -c '^hl.bind' reference/bindings.lua)" -ge 50
        echo ok > $out
      '';

  # The shell loads in Quickshell on a Wayland compositor (Weston without a screen): every file of
  # shell/qml, the QML module of StrixUI, no QML error. PipeWire, Hyprland and D-Bus are missing
  # here, their warnings are expected.
  shell =
    let
      cfg = reference.config;
      ui = cfg.${branding.id}.ui.package;
    in
    assert cfg.environment.etc ? "xdg/quickshell/${branding.id}";
    assert cfg.environment.etc ? "xdg/quickshell/${branding.id}-greeter";
    assert lib.hasSuffix "-greeter" cfg.services.greetd.settings.default_session.command;
    assert cfg.systemd.user.services ? "${branding.id}-shell";
    assert cfg.security.pam.services ? "${branding.id}-lock";
    assert cfg.${branding.id}.search.enable;
    assert cfg.systemd.user.services ? "${branding.id}-clipboard";
    assert cfg.services.upower.enable;
    pkgs.runCommand "check-shell"
      {
        nativeBuildInputs = [ pkgs.quickshell pkgs.weston pkgs.gnugrep pkgs.coreutils ];
      }
      ''
        export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/run
        mkdir -p -m 0700 $XDG_RUNTIME_DIR $TMPDIR/xdg/quickshell
        cp -r ${../shell/qml} $TMPDIR/xdg/quickshell/${branding.id}
        cp -r ${../shell/greeter} $TMPDIR/xdg/quickshell/${branding.id}-greeter
        weston --backend=headless --socket=wl-check --width=1280 --height=800 > weston.log 2>&1 &
        for _ in $(seq 50); do [ -S $XDG_RUNTIME_DIR/wl-check ] && break; sleep 0.2; done
        WAYLAND_DISPLAY=wl-check XDG_CONFIG_DIRS=$TMPDIR/xdg QT_QPA_PLATFORM=wayland \
          QML_IMPORT_PATH=${ui}/share/${branding.id}-ui/qml \
          timeout 20 qs -c ${branding.id} > log.txt 2>&1 || true
        # the login, as greetd would start it (without greetd here)
        WAYLAND_DISPLAY=wl-check XDG_CONFIG_DIRS=$TMPDIR/xdg QT_QPA_PLATFORM=wayland \
          QML_IMPORT_PATH=${ui}/share/${branding.id}-ui/qml GREETER_STATE=$TMPDIR \
          timeout 15 qs -c ${branding.id}-greeter > greeter.txt 2>&1 || true
        kill %1 || true
        for log in log.txt greeter.txt; do
          cat $log
          grep -q "Configuration Loaded" $log
          if grep -E "Failed to load|\.qml\[[0-9]+|\.qml:[0-9]+|is not a type|ReferenceError|TypeError|Cannot assign" $log; then
            echo "QML problems in $log, see above"
            exit 1
          fi
        done
        echo ok > $out
      '';

  # The Store: the service with its unit tests, the index service, the user service and the
  # polkit rule that lets the session run exactly `<id>-apps add|remove <package>` (Q4)
  store =
    let
      cfg = reference.config;
      rule = cfg.security.polkit.extraConfig;
    in
    assert cfg.${branding.id}.store.enable;
    assert cfg.systemd.services ? "${branding.id}-store-index";
    assert cfg.systemd.user.services ? "${branding.id}-store";
    assert lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe cfg.system.build.distroTools.apps)) (builtins.unsafeDiscardStringContext rule);
    assert lib.hasInfix "(add|remove)" rule;
    assert lib.hasInfix "AUTH_ADMIN_KEEP" rule;
    # nixpkgs is named in the index unit, but not kept in the system
    assert !(builtins.hasContext cfg.systemd.services."${branding.id}-store-index".environment.NIXPKGS);
    cfg.${branding.id}.store.package;

  # The search service with its unit tests (golden queries, the 5 ms budget, the socket), and the
  # system menu and command files checked by it: unique ids, groups that exist, no emoji
  search =
    let
      search = pkgs.callPackage ../packages/search { };
    in
    pkgs.runCommand "check-search" { } ''
      ${lib.getExe search} check
      touch $out
    '';

  # The user service evaluates on the reference machine
  search-module =
    let
      cfg = (reference.extendModules { modules = [ { ${branding.id}.search.enable = true; } ]; }).config;
      unit = cfg.systemd.user.services."${branding.id}-search";
    in
    assert lib.hasSuffix "-search serve" unit.serviceConfig.ExecStart;
    builtins.seq cfg.system.build.toplevel.drvPath (ok "search-module");

  # The splash follows the theme: one Plymouth theme per variant, the default
  # one set, the initrd unit that picks the stored one, /etc pointing at /run
  theme-splash =
    let
      cfg = reference.config;
      names = map (p: p.name) cfg.boot.plymouth.themePackages;
      unit = "${branding.id}-theme-boot";
    in
    assert cfg.boot.plymouth.theme == "${branding.id}-saturnus-dark";
    assert lib.all (name: lib.elem name names) (
      map (god: "${branding.id}-${god}-dark") gods
    );
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
    assert (with' "janus").boot.plymouth.theme == "${branding.id}-janus-dark";
    assert (with' "pluto:dark").boot.plymouth.theme == "${branding.id}-pluto-dark";
    ok "theme-default";

  # Theme repositories: mkSystem finds themes.json beside apps.json, the copied
  # themes join the gods and pass the engine's check. A theme with a god's id, a
  # missing folder or a bad id is left out with a warning, never an error.
  theme-repos =
    let
      machine = self.lib.mkSystem {
        modules = [ ../hosts/reference ];
        apps = ./fixtures/repos/apps.json;
      };
      cfg = machine.config;
      names = map (p: p.name) cfg.boot.plymouth.themePackages;
    in
    assert reference.config.${branding.id}.theme.repos.file == null;
    assert cfg.${branding.id}.theme.repos.file != null;
    assert lib.elem "${branding.id}-lucifer-dark" names;
    assert lib.length names == lib.length gods + 1;
    cfg.system.build.themes;

  # strix-update with the theme repositories: when it fetches, when it rebuilds,
  # that a theme repository never stops an update; --themes alone
  update-tool =
    pkgs.runCommand "check-update-tool"
      {
        nativeBuildInputs = with pkgs; [ bash coreutils util-linux diffutils jq ];
      }
      ''
        bash ${./update.sh} ${../modules/tools/common.sh} ${../modules/tools/update.sh} | tee $out
      '';

  # The update tool itself passes shellcheck (writeShellApplication runs it)
  update-tool-build = reference.config.system.build.distroTools.update;

  # A default theme that does not exist stops the build
  theme-default-unknown = mustFail "theme-default-unknown" (toplevelWith { ${branding.id}.theme.default = "nope"; });
  theme-default-unknown-variant = mustFail "theme-default-unknown-variant" (
    toplevelWith { ${branding.id}.theme.default = "janus:light"; }
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

  # The test machine goes through mkSystem like a real installation
  eval-reference = builtins.seq reference.config.system.build.toplevel.drvPath (ok "eval-reference");

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

  # Secure Boot (main): the machine signs after every boot loader install and
  # lets the installer make the boot entry for shim; the ISO's GRUB has the
  # SBAT section shim asks for. The boot chain itself: tests/secure-boot.nix
  secure-boot =
    let
      cfg = reference.config;
      isoPkgs = configs."${branding.id}-iso".pkgs;
    in
    assert cfg.${branding.id}.secureBoot.enable;
    assert lib.hasInfix "${branding.id}-secure-boot sign" cfg.boot.loader.systemd-boot.extraInstallCommands;
    assert !cfg.boot.loader.efi.canTouchEfiVariables;
    assert lib.any (p: (p.pname or "") == "mokutil") cfg.environment.systemPackages;
    assert isoPkgs.grub2_efi ? sbat;
    assert lib.hasInfix "grub,7," (builtins.readFile isoPkgs.grub2_efi.sbat);
    assert lib.any (p: (p.pname or "") == "mokutil") iso.environment.systemPackages;
    ok "secure-boot";

  # Turned off, nothing of it is left in the boot loader install
  secure-boot-off =
    let
      cfg = (reference.extendModules { modules = [ { ${branding.id}.secureBoot.enable = false; } ]; }).config;
    in
    assert !lib.hasInfix "secure-boot" cfg.boot.loader.systemd-boot.extraInstallCommands;
    assert cfg.boot.loader.efi.canTouchEfiVariables;
    ok "secure-boot-off";

  # The binary cache is only used once its public key is in modules/cache.nix
  cache =
    let
      settings = reference.config.nix.settings;
      used = settings ? extra-substituters && settings.extra-substituters != [ ];
    in
    assert used -> lib.all (url: lib.hasPrefix "https://" url) settings.extra-substituters;
    assert used -> settings.extra-trusted-public-keys != [ ];
    ok "cache";

  # Neovim is the editor and follows the theme through its colorscheme files
  neovim =
    let
      cfg = reference.config;
    in
    assert cfg.programs.neovim.enable && cfg.programs.neovim.defaultEditor;
    assert cfg.environment.etc ? "xdg/nvim/colors/${branding.id}.lua";
    assert cfg.environment.etc ? "xdg/nvim/plugin/${branding.id}.lua";
    ok "neovim";
}
