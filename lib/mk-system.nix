# strix.lib.mkSystem: builds a system from the files in /etc/nixos.
#
#   nixosConfigurations.strix = strix.lib.mkSystem {
#     modules = [ ./hardware.nix ./machine.nix ];
#     apps = ./apps.json;
#   };
#
# themes.json (the connected theme repositories) is taken from next to
# apps.json when it is there, so machines installed before it existed need no
# change to their flake.nix. `themes = ./themes.json;` names it directly.
{ self, nixpkgs, version }:

{
  modules ? [ ],
  apps ? null,
  themes ? null,
}:

let
  branding = import ../branding.nix;
  besideApps = dirOf apps + "/themes.json";
  themesFile =
    if themes != null then
      themes
    else if apps != null && builtins.pathExists besideApps then
      besideApps
    else
      null;
in
nixpkgs.lib.nixosSystem {
  # No system argument: hardware.nix sets nixpkgs.hostPlatform.
  specialArgs = {
    distroFlake = self;
    inherit version;
  };
  modules = [
    self.nixosModules.default
    {
      ${branding.id} = {
        apps.file = apps;
        theme.repos.file = themesFile;
      };
    }
  ]
  ++ modules;
}
