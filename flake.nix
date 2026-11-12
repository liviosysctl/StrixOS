{
  description = "A NixOS-based distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The design system: the eight god themes, the QML module, wallpapers and
    # fonts. Only data, so not read as a flake. Moves with every update (update.yml).
    strixui = {
      url = "github:liviosysctl/StrixUI";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, disko, strixui, ... }:
    let
      # The only place with the version number. bump_version.py replaces exactly this line.
      version = "0.1.0";

      # Where installed machines get updates from. Machines installed from a
      # release ISO follow ref (stable, moved by the release workflow). The dev
      # ISO from every push follows devRef, so test machines get fixes before
      # a release. The branches differ between main (school proof of concept)
      # and personal.
      upstream = {
        owner = "liviosysctl";
        repo = "strixos";
        ref = "stable";
        devRef = "main";
      };

      branding = import ./branding.nix;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      mkSystem = import ./lib/mk-system.nix { inherit self nixpkgs version; };

      # Template for /etc/nixos with the distro name and the branch to follow
      # filled in, for the installer
      machineTemplate =
        ref:
        pkgs.runCommand "${branding.id}-machine-template" { } ''
          cp -r ${./templates/machine} $out
          chmod -R u+w $out
          substituteInPlace $out/flake.nix $out/machine.nix --replace-fail @distroId@ ${branding.id}
          substituteInPlace $out/flake.nix \
            --replace-fail @distroUrl@ github:${upstream.owner}/${upstream.repo}/${ref}
        '';

      # A finished flake.lock for /etc/nixos that points at exactly this commit,
      # so the installed system matches the ISO and needs no download to lock.
      # Only possible from a clean, committed tree with a flake.lock (null
      # otherwise). Then the installer runs nix flake lock itself, which needs
      # a network.
      machineLock =
        ref:
        if builtins.pathExists ./flake.lock && self ? rev then
          let
            own = builtins.fromJSON (builtins.readFile ./flake.lock);
            github = {
              type = "github";
              inherit (upstream) owner repo;
            };
            prefixFollows =
              node:
              node
              // lib.optionalAttrs (node ? inputs) {
                inputs = lib.mapAttrs (
                  _: target: if builtins.isList target then [ branding.id ] ++ target else target
                ) node.inputs;
              };
          in
          pkgs.writeText "flake.lock" (
            builtins.toJSON {
              inherit (own) version;
              root = "root";
              # "follows" entries are paths from the root of the lock file.
              # Here the distro is no longer the root but one input below it,
              # so every such path gets its name in front.
              nodes = (lib.mapAttrs (_: prefixFollows) (removeAttrs own.nodes [ "root" ])) // {
                root.inputs.${branding.id} = branding.id;
                ${branding.id} = {
                  inputs = own.nodes.root.inputs;
                  locked = github // {
                    inherit (self) rev narHash lastModified;
                  };
                  original = github // {
                    inherit ref;
                  };
                };
              };
            }
          )
        else
          null;

      mkInstaller =
        ref:
        pkgs.callPackage ./installer/package.nix {
          inherit version;
          inherit (disko.packages.${system}) disko;
          machineTemplate = machineTemplate ref;
          machineLock = machineLock ref;
          themeFile = themes.installer;
        };

      iso = self.nixosConfigurations."${branding.id}-iso";

      # The themes of StrixUI with the default from themes/default.nix
      themes = import ./lib/themes.nix {
        inherit pkgs;
        builtin = "${strixui}/design-system/themes";
      };
    in
    {
      lib = { inherit version mkSystem; };

      # All distro modules together. Meant to be used through lib.mkSystem.
      nixosModules.default = {
        imports = [
          disko.nixosModules.disko
          ./modules
        ];
      };

      # Distro modules. Every module reads the name from branding.nix itself.
      nixosModules.storage = {
        imports = [
          disko.nixosModules.disko
          ./modules/storage/btrfs.nix
        ];
      };

      nixosConfigurations = {
        # Installer medium
        "${branding.id}-iso" = nixpkgs.lib.nixosSystem {
          specialArgs = {
            distroFlake = self;
            inherit version;
          };
          modules = [
            ./iso
            { nixpkgs.hostPlatform = system; }
          ];
        };

        # Made-up machine for CI and the ISO's store
        "${branding.id}-reference" = mkSystem {
          modules = [ ./hosts/reference ];
          apps = ./templates/machine/apps.json;
        };
      };

      packages.${system} = {
        # nix build .#iso
        iso = iso.config.system.build.isoImage;

        # For testing: faster compression (the ISO gets slightly larger), and
        # machines installed from it follow devRef instead of stable
        iso-dev =
          (iso.extendModules {
            modules = [
              {
                isoImage.squashfsCompression = "zstd -Xcompression-level 3";
                ${branding.id}.iso.dev = true;
              }
            ];
          }).config.system.build.isoImage;

        # Installed machines follow stable (release ISO) or devRef (dev ISO)
        installer = mkInstaller upstream.ref;
        installer-dev = mkInstaller upstream.devRef;

        # The theme engine and the checked themes folder
        theme-engine = themes.engine;
        themes = themes.dir;

        # The design system: QML module, wallpapers, fonts
        ui = pkgs.callPackage ./packages/ui { src = strixui; };

        # The search service, with the system menu and the command files (10-search in the plan)
        search = pkgs.callPackage ./packages/search { };

        machine-template = machineTemplate upstream.ref;

        default = self.packages.${system}.iso;
      }
      // lib.optionalAttrs (machineLock upstream.ref != null) {
        machine-lock = machineLock upstream.ref;
      };

      checks.${system} = import ./tests/eval.nix { inherit self pkgs; };

      # Tests that boot VMs, too slow for every push: nix build .#tests.theme -L
      legacyPackages.${system}.tests = {
        theme = import ./tests/theme-vm.nix { inherit self pkgs; };
        # Hyprland after the login, a window in the theme's colors, a switch while it runs
        desktop = import ./tests/desktop-vm.nix { inherit self pkgs; };
        # The installer on an empty disk, then the installed disk booted.
        # Needs a clean, committed tree. nix build .#tests.install -L
        install = import ./tests/install.nix { inherit self pkgs; };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.git-cliff
          # The theme engine
          pkgs.cargo
          pkgs.rustc
          pkgs.clippy
          pkgs.rustfmt
        ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
