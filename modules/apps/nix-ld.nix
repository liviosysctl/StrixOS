# Programs built for other Linux systems: what npx, an editor or a language server downloads, or a
# release from GitHub. They look for /lib64/ld-linux-x86-64.so.2 and the libraries beside it, which
# NixOS does not have; nix-ld puts a loader there that finds them in the system. Beyond the ones
# nix-ld always gives (from systemd and Nix), these are what such programs need most often.
{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      curl
      sqlite
      xz
    ];
  };
}
