{
  description = "Diese Maschine";

  # Die Distro ist der einzige Input. nixpkgs kommt aus ihrer flake.lock,
  # so läuft immer eine Kombination, die schon gebaut und getestet wurde.
  # "stable" bewegt sich nur bei Releases.
  inputs.@distroId@.url = "github:liviosysctl/strixos/stable";

  outputs =
    { @distroId@, ... }:
    {
      # Immer "@distroId@", nicht der Rechnername: so bricht ein neuer Name nichts.
      nixosConfigurations.@distroId@ = @distroId@.lib.mkSystem {
        modules = [
          ./hardware.nix
          ./machine.nix
        ];
        apps = ./apps.json;
      };
    };
}
