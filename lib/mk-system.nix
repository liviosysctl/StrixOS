# strix.lib.mkSystem: builds a system from the files in /etc/nixos.
#
#   nixosConfigurations.strix = strix.lib.mkSystem {
#     modules = [ ./hardware.nix ./machine.nix ];
#     apps = ./apps.json;
#   };
{ self, nixpkgs, version }:

{
  modules ? [ ],
  apps ? null,
}:

let
  branding = import ../branding.nix;
in
nixpkgs.lib.nixosSystem {
  # No system argument: hardware.nix sets nixpkgs.hostPlatform.
  specialArgs = {
    distroFlake = self;
    inherit version;
  };
  modules = [
    self.nixosModules.default
    { ${branding.id}.apps.file = apps; }
  ]
  ++ modules;
}
