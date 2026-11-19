# GRUB for installed machines as one image, the same on every machine: shim
# starts it from EFI/BOOT/grubx64.efi, and it reads grub/grub.cfg from the ESP
# it was loaded from (a prefix without a device means that device). Because the
# image does not depend on the machine, CI can sign it once with the distro key
# (secure-boot/signatures), and a machine that trusts the ISO trusts it too.
#
# Every module grub.cfg uses is built in: under Secure Boot GRUB loads no module
# from disk. NixOS's grub.cfg, os-prober's entries (Windows is chainloaded, the
# firmware checks its signature), the theme and the firmware settings.
{
  runCommand,
  writeText,
  grub-sb,
}:

let
  branding = import ../../branding.nix;

  modules = [
    "normal" "configfile" "echo" "test" "true" "sleep" "reboot" "halt" "minicmd" "ls" "cat"
    "probe" "regexp" "search" "search_fs_uuid" "search_fs_file" "search_label" "part_gpt"
    "part_msdos" "fat" "ext2" "btrfs" "linux" "chain" "efifwsetup" "loadenv" "keystatus"
    "all_video" "efi_gop" "efi_uga" "video_bochs" "video_cirrus" "gfxterm" "gfxterm_background"
    "gfxmenu" "png" "font"
  ];

  # $prefix is GRUB's: (the ESP)/grub
  early = writeText "grub-early.cfg" ''
    configfile $prefix/grub.cfg
  '';
in
runCommand "${branding.id}-grub-image" { } ''
  mkdir $out
  ${grub-sb}/bin/grub-mkimage --directory ${grub-sb}/lib/grub/x86_64-efi \
    --format x86_64-efi --prefix /grub --config ${early} \
    --output $out/grubx64.efi ${toString modules}
''
