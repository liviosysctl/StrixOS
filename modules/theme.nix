# Themes: the theme engine and every part of the system that follows the theme.
#
# `sudo <id>-theme set <theme>` switches at runtime, without a rebuild:
#   - tokens.json in /run/<id>/theme, for programs that read the colors
#     directly (Quickshell later), right away
#   - the palette of the virtual consoles, right away
#   - the Plymouth splash at shutdown and reboot, right away
#   - the Plymouth splash at boot, from the next boot: a unit in the initrd
#     reads the theme from an EFI variable before Plymouth starts
# The choice is stored in /var/lib/<id>/theme/selection. At every boot the
# <id>-theme service applies it again.
#
# The themes of the distribution are the eight gods of StrixUI (flake input).
# Themes from outside come from theme repositories, listed in themes.json next
# to the machine configuration: `<id>-theme repos` fetches, checks and copies
# them into themes/ beside it, this module only reads those copies.
{ config, lib, pkgs, distroFlake, ... }:

let
  branding = import ../branding.nix;
  cfg = config.${branding.id}.theme;

  builtin = "${distroFlake.inputs.strixui}/design-system/themes";
  builtinIds = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir builtin)
  );

  # themes.json and the copies of the checked themes in themes/ next to it.
  # A theme that cannot be used is left out with a warning, never an error:
  # a theme repository must not stop an update.
  repos =
    if cfg.repos.file == null then
      [ ]
    else
      let
        data = lib.importJSON cfg.repos.file;
      in
      if (data.version or 0) == 1 then
        data.repos or [ ]
      else
        lib.warn "themes.json has format ${toString (data.version or "?")}, only format 1 is read; no outside themes" [ ];
  reposDir = dirOf cfg.repos.file + "/themes";
  repoTheme =
    repo: themeId:
    let
      path = reposDir + "/${themeId}";
      from = repo.name or repo.url;
    in
    if builtins.match "[a-z][a-z0-9-]*" themeId == null then
      lib.warn "themes.json: \"${themeId}\" of ${from} is no theme id, left out" [ ]
    else if lib.elem themeId builtinIds then
      lib.warn "themes.json: ${themeId} of ${from} has the id of a theme of ${branding.name}, left out" [ ]
    else if !builtins.pathExists (path + "/theme.toml") then
      lib.warn "themes.json: themes/${themeId} of ${from} is missing, run ${branding.id}-theme repos update and rebuild" [ ]
    else
      [ (lib.nameValuePair themeId path) ];
  repoThemes = builtins.listToAttrs (
    lib.concatMap (repo: lib.concatMap (repoTheme repo) (repo.themes or [ ])) repos
  );

  themes = import ../lib/themes.nix {
    inherit pkgs builtin;
    inherit (cfg) default;
    extraThemes = removeAttrs repoThemes (builtins.attrNames cfg.extraThemes) // cfg.extraThemes;
  };
  exe = lib.getExe themes.engine;
  resolved = themes.resolve cfg.default;

  stateDir = "/var/lib/${branding.id}/theme";
  runtimeDir = "/run/${branding.id}/theme";

  # An own vendor GUID keeps the variable apart from every other. It does not
  # depend on the name, renaming the distro keeps it.
  efiVariable = "Theme-595702b9-5e56-4cc8-9b1a-d145cfd71953";

  plymouth = config.boot.plymouth;
  plymouthNames = map (v: v.plymouth) themes.variants;
  # The splash follows the theme as long as one of the theme's Plymouth themes
  # is set (the default). Another Plymouth theme is left alone.
  splash = plymouth.enable && lib.elem plymouth.theme plymouthNames;
  # The plymouthd.conf NixOS writes, with Theme= set to the default
  plymouthBaseConf = config.boot.initrd.systemd.contents."/etc/plymouth/plymouthd.conf".source;

  env = {
    THEMES_DIR = "${themes.dir}";
    BUILTIN_THEMES = builtin;
    GIT = lib.getExe pkgs.gitMinimal;
    STATE_DIR = stateDir;
    RUNTIME_DIR = runtimeDir;
    DEFAULT_THEME = cfg.default;
  }
  // lib.optionalAttrs splash {
    PLYMOUTH_PREFIX = themes.plymouthPrefix;
    PLYMOUTH_BASE_CONF = "${plymouthBaseConf}";
    PLYMOUTH_THEMES = "/etc/plymouth/themes";
    EFI_VARIABLE = efiVariable;
  };

  # The command for people, with the settings of this system and tab
  # completion for bash, zsh and fish
  command =
    let
      name = "${branding.id}-theme";
      completions = ../packages/theme-engine/completions;
      fill = ''--subst-var-by command ${name} --subst-var-by function ${lib.replaceStrings [ "-" ] [ "_" ] name}'';
    in
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = name;
      }
      ''
        makeBinaryWrapper ${exe} $out/bin/${name} \
          ${lib.concatStringsSep " " (lib.mapAttrsToList (n: value: "--set ${n} ${lib.escapeShellArg value}") env)} \
          --set-default REPOS_FILE /etc/nixos/themes.json
        mkdir -p $out/share/bash-completion/completions $out/share/zsh/site-functions $out/share/fish/vendor_completions.d
        substitute ${completions}/theme.bash $out/share/bash-completion/completions/${name} ${fill}
        substitute ${completions}/theme.zsh $out/share/zsh/site-functions/_${name} ${fill}
        substitute ${completions}/theme.fish $out/share/fish/vendor_completions.d/${name}.fish ${fill}
      '';

  # The GRUB menu follows the theme too: every variant's GRUB theme, by
  # selection, and a script that copies the one of the current theme to the
  # ESP. The service below runs it when the theme changes, the boot loader
  # install after every switch (a new ESP, a new default).
  grub = config.boot.loader.grub;
  grubThemes = pkgs.linkFarm "${branding.id}-grub-themes" (
    lib.mapAttrsToList (selection: path: { name = selection; inherit path; }) themes.grubThemes
  );
  defaultSelection = "${resolved.theme or ""}:${resolved.variant or ""}";
  grubTheme = pkgs.writeShellScript "${branding.id}-grub-theme" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.diffutils pkgs.jq ]}
    esp=${config.boot.loader.efi.efiSysMountPoint}
    [ -d "$esp/grub" ] || exit 0
    selection=${lib.escapeShellArg defaultSelection}
    if [ -s ${runtimeDir}/tokens.json ]; then
      current=$(jq -r '.theme + ":" + .variant' ${runtimeDir}/tokens.json 2>/dev/null || true)
      [ -e "${grubThemes}/$current" ] && selection=$current
    fi
    source=${grubThemes}/$selection
    target=$esp/grub/${branding.id}/theme
    # Unchanged themes are not written again
    if [ -d "$target" ] && diff -rq "$source/" "$target/" >/dev/null 2>&1; then
      exit 0
    fi
    mkdir -p "$esp/grub/${branding.id}"
    rm -rf "$target.new"
    cp -rL "$source" "$target.new"
    chmod -R u+w "$target.new"
    rm -rf "$target"
    mv "$target.new" "$target"
    echo "Boot menu: $selection"
  '';

  # Every variant's Plymouth theme for the initrd. NixOS only copies the one
  # set in boot.plymouth.theme, the unit below may pick any of them.
  # Like NixOS, the paths in the .plymouth files are moved to the new folder.
  initrdThemes = pkgs.runCommand "${branding.id}-plymouth-initrd-themes" { } ''
    mkdir -p $out
    ${lib.concatMapStrings (package: ''
      cp -r ${package}/share/plymouth/themes/* $out/
    '') themes.plymouthThemes}
    chmod -R u+w $out
    for theme in $out/*/*.plymouth; do
      sed -i "s,${builtins.storeDir}/[^/]*/share/plymouth/themes,$out," "$theme"
    done
  '';
in
{
  options.${branding.id}.theme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Themes: the ${branding.id}-theme command and the parts of the system that follow the theme.";
    };

    default = lib.mkOption {
      type = lib.types.str;
      default = import ../themes/default.nix;
      defaultText = lib.literalExpression "import ./themes/default.nix";
      example = "janus";
      description = ''
        The theme in use until another one is chosen with `${branding.id}-theme set`,
        as `<theme>` or `<theme>:<variant>`. Also the theme of the boot splash
        before anything is chosen.
      '';
    };

    repos.file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        themes.json from /etc/nixos: the connected theme repositories. Their
        checked themes are read from the folder themes/ next to it. Written by
        `${branding.id}-theme repos` and `${branding.id}-update`; lib.mkSystem
        sets this when the file is there.
      '';
    };

    extraThemes = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression "{ my-theme = ./themes/my-theme; }";
      description = ''
        More theme folders, by id, next to the ones that come with the
        distribution. Each folder holds a theme.toml. They are checked while
        building, a broken theme stops the build.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The ${branding.id}-theme command with the settings of this system.";
    };

    grubTheme = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The GRUB theme of the default theme (the ISO's boot menu).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = resolved.error == null;
            message = "${branding.id}.theme.default: ${toString resolved.error}";
          }
        ];

        ${branding.id}.theme = {
          package = command;
          grubTheme = themes.grubTheme defaultSelection;
        };
        environment.systemPackages = [ command ];
        system.build.themes = themes.dir;

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0755 root root -"
          "d ${runtimeDir} 0755 root root -"
        ];

        systemd.services."${branding.id}-theme" = {
          description = "Apply the selected theme";
          wantedBy = [ "multi-user.target" ];
          # After Plymouth has let go of the console, before a graphical session
          after = [
            "systemd-tmpfiles-setup.service"
            "systemd-vconsole-setup.service"
            "plymouth-quit.service"
          ];
          before = [ "display-manager.service" ];
          environment = env;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${exe} apply";
          };
        };
      }

      # The default theme's splash, unless another Plymouth theme is set
      (lib.mkIf plymouth.enable {
        boot.plymouth.theme = lib.mkIf (resolved.error == null) (
          lib.mkDefault (themes.plymouthName resolved.theme resolved.variant)
        );
        boot.plymouth.themePackages = themes.plymouthThemes;
      })

      (lib.mkIf splash {
        # Shutdown and reboot: plymouthd reads its config from /run, where
        # the service writes the current theme. Until then a copy of the
        # default config sits there, so plymouthd always finds one.
        environment.etc."plymouth/plymouthd.conf".source = lib.mkForce "${runtimeDir}/plymouthd.conf";
        systemd.tmpfiles.rules = [ "C ${runtimeDir}/plymouthd.conf - - - - ${plymouthBaseConf}" ];
      })

      (lib.mkIf splash {
        boot.initrd.systemd.contents."/etc/plymouth/themes".source = lib.mkForce initrdThemes;
        boot.initrd.systemd.storePaths = [ exe ];

        # Before Plymouth starts: write the stored theme's splash into its
        # config. Never fails the boot, on any problem the default stays.
        boot.initrd.systemd.services."${branding.id}-theme-boot" = {
          description = "Pick the boot splash of the selected theme";
          wantedBy = [ "plymouth-start.service" ];
          before = [ "plymouth-start.service" ];
          unitConfig.DefaultDependencies = false;
          environment = {
            EFI_VARIABLE = efiVariable;
            PLYMOUTH_PREFIX = themes.plymouthPrefix;
            PLYMOUTH_THEMES = "/etc/plymouth/themes";
            PLYMOUTH_CONF = "/etc/plymouth/plymouthd.conf";
          };
          serviceConfig = {
            Type = "oneshot";
            # plymouth-start is pulled in more than once in the initrd; once is enough
            RemainAfterExit = true;
            ExecStart = "${exe} boot-select";
          };
        };
      })

      (lib.mkIf (grub.enable && grub.efiSupport) {
        boot.loader.grub.extraInstallCommands = ''
          ${grubTheme}
        '';

        # tokens.json changes with every `${branding.id}-theme set` and at every boot
        systemd.services."${branding.id}-grub-theme" = {
          description = "Draw the boot menu in the selected theme";
          after = [ "${branding.id}-theme.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = grubTheme;
          };
        };
        systemd.paths."${branding.id}-grub-theme" = {
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathChanged = "${runtimeDir}/tokens.json";
        };
      })
    ]
  );
}
