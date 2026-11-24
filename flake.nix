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
    # Zen, the browser of Strix (not in nixpkgs). Its Home Manager module is not used, so that
    # input points nowhere.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "";
    };
  };

  outputs =
    { self, nixpkgs, disko, strixui, ... }:
    let
      # The only place with the version number. bump_version.py replaces exactly this line.
      version = "1.2.0";

      # Where installed machines get updates from. The proof of concept has no
      # releases: every machine installed from its ISO follows the branch
      # m245-poc, so strix-update brings what CI last built.
      upstream = {
        owner = "liviosysctl";
        repo = "strixos";
        ref = "m245-poc";
        devRef = "m245-poc";
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
        builtin = import ./lib/builtin-themes.nix strixui;
        inherit strixui;
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

        # The Store service (main only)
        store = pkgs.callPackage ./packages/store { };

        # Secure Boot (main only): shim and MokManager signed by Microsoft and
        # Debian, GRUB with an SBAT section for the ISO, the script that signs
        # the ISO (CI, key from a secret), and the one that makes that key
        shim = pkgs.callPackage ./packages/shim { };
        grub-sb = pkgs.callPackage ./packages/grub-sb {
          homepage = "https://github.com/${upstream.owner}/${upstream.repo}";
        };
        sign-iso = pkgs.callPackage ./packages/sign-iso { inherit (self.packages.${system}) shim; };

        # GRUB for installed machines, the same image everywhere (packages/grub-image)
        grub-image = pkgs.callPackage ./packages/grub-image { inherit (self.packages.${system}) grub-sb; };

        # The boot files of an installed machine that CI signs with the distro key
        # (.github/scripts/sign-boot-files.sh): GRUB and the kernel of the
        # reference system, as links, so building it fetches them.
        boot-files =
          let
            ref = self.nixosConfigurations."${branding.id}-reference".config;
          in
          pkgs.linkFarm "${branding.id}-boot-files" {
            "grubx64.efi" = "${self.packages.${system}.grub-image}/grubx64.efi";
            kernel = "${ref.boot.kernelPackages.kernel}/${ref.system.boot.loader.kernelFile}";
          };
        secure-boot-key = pkgs.callPackage ./packages/secure-boot-key { };

        # The design system: QML module, wallpapers, fonts
        ui = pkgs.callPackage ./packages/ui { src = strixui; };

        # The search service, with the system menu and the command files (10-search in the plan)
        search = pkgs.callPackage ./packages/search { };

        machine-template = machineTemplate upstream.ref;

        # What CI pushes to the binary cache (modules/cache.nix): everything
        # an install or an update would otherwise compile. Pushing takes the
        # closure; Cachix leaves out what cache.nixos.org already has.
        cache-roots = pkgs.linkFarm "${branding.id}-cache-roots" {
          inherit (self.packages.${system}) installer installer-dev theme-engine store search ui;
          reference = self.nixosConfigurations."${branding.id}-reference".config.system.build.toplevel;
        };

        default = self.packages.${system}.iso;
      }
      // lib.optionalAttrs (machineLock upstream.ref != null) {
        machine-lock = machineLock upstream.ref;
      };

      checks.${system} = import ./tests/eval.nix { inherit self pkgs; } // {
        # Every boot file CI signs has a signature in secure-boot/signatures that
        # fits the file and the distro certificate. Fails after a kernel update
        # until CI has signed the new kernel (the sign job runs before this check).
        boot-signatures =
          pkgs.runCommand "${branding.id}-boot-signatures" { nativeBuildInputs = [ pkgs.sbsigntool ]; }
            ''
              for file in ${self.packages.${system}.boot-files}/*; do
                sha=$(sha256sum < "$file" | cut -d " " -f 1)
                sig=${./secure-boot/signatures}/$sha.p7
                if [ ! -e "$sig" ]; then
                  echo "$(basename "$file") ($sha) has no signature yet: CI signs it on the next push to m245-poc" >&2
                  exit 1
                fi
                install -m 0644 "$file" signed.efi
                sbattach --attach "$sig" signed.efi >/dev/null
                sbverify --cert ${./secure-boot}/${branding.id}.crt signed.efi
              done
              touch $out
            '';
      };

      # Tests that boot VMs, too slow for every push: nix build .#tests.theme -L
      legacyPackages.${system}.tests = {
        theme = import ./tests/theme-vm.nix { inherit self pkgs; };
        # Hyprland after the login, a window in the theme's colors, a switch while it runs
        desktop = import ./tests/desktop-vm.nix { inherit self pkgs; };
        live = import ./tests/live-vm.nix { inherit self pkgs; };
        # The installer on an empty disk, then the installed disk booted.
        # Needs a clean, committed tree. nix build .#tests.install -L
        install = import ./tests/install.nix { inherit self pkgs; };
      }
      # Secure Boot with OVMF: the signed ISO, an installed machine
      # (nix build .#tests.secure-boot-iso -L, .#tests.secure-boot -L)
      // import ./tests/secure-boot.nix { inherit self pkgs; };

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
