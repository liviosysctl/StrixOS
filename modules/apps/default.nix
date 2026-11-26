# The terminal's tools, the packages added on this machine, and programs built for other systems.
{
  imports = [
    ./terminal.nix
    ./prompt.nix
    ./neovim.nix
    ./fastfetch.nix
    ./packages.nix
    ./nix-ld.nix
  ];
}
