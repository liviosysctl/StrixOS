{
  description = "This machine";

  # The distro is the only input. nixpkgs comes from its flake.lock, so the
  # machine always runs a combination that was already built and tested.
  # "stable" only moves on releases.
  inputs.@distroId@.url = "github:liviosysctl/strixos/stable";

  outputs =
    { @distroId@, ... }:
    {
      # Always "@distroId@", not the host name: renaming the machine breaks nothing.
      nixosConfigurations.@distroId@ = @distroId@.lib.mkSystem {
        modules = [
          ./hardware.nix
          ./machine.nix
        ];
        apps = ./apps.json;
      };
    };
}
