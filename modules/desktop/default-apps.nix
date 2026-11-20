# What opens a file: text in Neovim, pictures in Loupe, videos in mpv, archives in File Roller, and
# Amberol for music. The live session of the ISO has none of them.
{ config, lib, pkgs, ... }:

let
  branding = import ../../branding.nix;
  id = branding.id;
  cfg = config.${id}.desktop;

  # Neovim is the editor: text opened from Files or elsewhere goes to it in a Ghostty window
  neovimWindow = pkgs.makeDesktopItem {
    name = "${id}-neovim";
    desktopName = "Neovim";
    comment = "Edit text in Neovim";
    exec = "ghostty -e nvim %F";
    icon = "nvim";
    categories = [ "Utility" "TextEditor" ];
    mimeTypes = [ "text/plain" "text/markdown" "text/x-nix" "application/json" "application/toml" "application/x-shellscript" ];
    # Only for opening files; app lists and Search show Neovim's own entry
    noDisplay = true;
  };

  # mpv with the colors of the session's theme (mpv.conf of the theme engine), for the app and
  # the command alike
  mpvThemed = pkgs.writeShellScriptBin "mpv" ''
    for dir in ''${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR/${id}/theme"} /run/${id}/theme; do
      if [ -r "$dir/mpv.conf" ]; then
        exec ${lib.getExe pkgs.mpv} --include="$dir/mpv.conf" "$@"
      fi
    done
    exec ${lib.getExe pkgs.mpv} "$@"
  '';
in
{
  config = lib.mkIf cfg.enable {
    xdg.mime.defaultApplications = lib.mkIf (!cfg.live) (
      lib.genAttrs [
        "text/plain"
        "text/markdown"
        "text/x-nix"
        "application/json"
        "application/toml"
        "application/x-shellscript"
      ] (_: "${id}-neovim.desktop")
      // lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/svg+xml"
        "image/avif"
        "image/bmp"
        "image/tiff"
      ] (_: "org.gnome.Loupe.desktop")
      // lib.genAttrs [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "audio/x-wav"
      ] (_: "mpv.desktop")
      // lib.genAttrs [
        "application/zip"
        "application/x-tar"
        "application/x-compressed-tar"
        "application/x-xz-compressed-tar"
        "application/x-bzip2-compressed-tar"
        "application/zstd"
        "application/x-zstd-compressed-tar"
        "application/x-7z-compressed"
        "application/vnd.rar"
      ] (_: "org.gnome.FileRoller.desktop")
    );

    environment.systemPackages = lib.optionals (!cfg.live) (
      with pkgs;
      [
        neovimWindow
        amberol
        loupe
        mpv
        (lib.hiPrio mpvThemed)
        file-roller
      ]
    );
  };
}
