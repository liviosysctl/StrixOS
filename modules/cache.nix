# The binary cache of the distribution on Cachix. CI pushes the distro's own
# packages there (the Rust services, the shell, the installer and the parts of
# the reference system), so installed machines and the installer download them
# instead of compiling. Everything nixpkgs has stays on cache.nixos.org: Cachix
# leaves out every path that is already there.
#
# The cache is named after the distro id. Until publicKey is set, machines do
# not use it, so nothing breaks before the cache exists.
{ lib, ... }:

let
  branding = import ../branding.nix;

  # The public key from the cache's page on app.cachix.org ("Public key"),
  # e.g. "strix.cachix.org-1:AbC...=". null: the cache is not used yet.
  publicKey = "strix.cachix.org-1:+tcbOXJCi1bafZQO8yMMOdxKVFSKcrDUyKB2FXXELSk=";
in
{
  config = lib.mkIf (publicKey != null) {
    nix.settings = {
      extra-substituters = [ "https://${branding.id}.cachix.org" ];
      extra-trusted-public-keys = [ publicKey ];
    };
  };
}
