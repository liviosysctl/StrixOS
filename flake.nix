{
  description = "A NixOS-based distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, disko, ... }:
    let
      # The only place with the version number. bump_version.py replaces exactly this line.
      version = "0.1.0";

      # Where installed machines get updates from. The branch differs between
      # main (school proof of concept) and personal.
      upstream = {
        owner = "liviosysctl";
        repo = "strixos";
        ref = "main";
      };

      branding = import ./branding.nix;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      mkSystem = import ./lib/mk-system.nix { inherit self nixpkgs version; };

      iso = self.nixosConfigurations."${branding.id}-iso";
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

        # Test machine for VMware Workstation, with guest tools
        "${branding.id}-vmware" = mkSystem {
          modules = [ ./hosts/vmware ];
          apps = ./templates/machine/apps.json;
        };
      };

      packages.${system} = {
        # nix build .#iso
        iso = iso.config.system.build.isoImage;

        # Faster compression for test builds, the ISO gets slightly larger
        iso-dev =
          (iso.extendModules {
            modules = [ { isoImage.squashfsCompression = "zstd -Xcompression-level 3"; } ];
          }).config.system.build.isoImage;

        installer = pkgs.callPackage ./installer/package.nix { inherit version; };

        # Template for /etc/nixos with the distro name filled in, for the installer
        machine-template = pkgs.runCommand "${branding.id}-machine-template" { } ''
          cp -r ${./templates/machine} $out
          chmod -R u+w $out
          substituteInPlace $out/flake.nix $out/machine.nix --replace-fail @distroId@ ${branding.id}
          substituteInPlace $out/flake.nix \
            --replace-fail @distroUrl@ github:${upstream.owner}/${upstream.repo}/${upstream.ref}
        '';

        default = self.packages.${system}.iso;
      }
      # A finished flake.lock for /etc/nixos that points at exactly this commit,
      # so the installed system matches the ISO and needs no download to lock.
      # Only possible from a clean, committed tree with a flake.lock. Otherwise
      # the installer runs nix flake lock itself, which needs a network.
      // lib.optionalAttrs (builtins.pathExists ./flake.lock && self ? rev) {
        machine-lock =
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
                    inherit (upstream) ref;
                  };
                };
              };
            }
          );
      };

      checks.${system} = import ./tests/eval.nix { inherit self pkgs; };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git-cliff ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
