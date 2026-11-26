# Memory that does not run out at once, and what happens when it does.
{ lib, ... }:

{
  # Compressed swap in memory, used before the swap file on disk: a full memory slows the machine
  # down instead of freezing it. The swap file stays for hibernation.
  zramSwap = {
    enable = lib.mkDefault true;
    memoryPercent = 50;
    priority = 100;
  };

  # When memory and swap stay full anyway, systemd-oomd ends the app that takes the most (a
  # browser with many tabs, a build) before the whole machine stops answering. NixOS turns oomd
  # on, but watches only the system slices; the apps of a session live in the user slices.
  systemd.oomd = {
    enable = lib.mkDefault true;
    enableUserSlices = lib.mkDefault true;
  };
}
