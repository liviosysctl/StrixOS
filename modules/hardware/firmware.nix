# What a machine needs looked after without being asked: firmware updates and memory that does not
# run out at once.
{ lib, ... }:

{
  # Firmware of the machine and its devices from the LVFS. <id>-update says when there is new
  # firmware; `fwupdmgr update` installs it.
  services.fwupd.enable = lib.mkDefault true;

  # Compressed swap in memory, used before the swap file on disk: a full memory slows the machine
  # down instead of freezing it. The swap file stays for hibernation.
  zramSwap = {
    enable = lib.mkDefault true;
    memoryPercent = 50;
    priority = 100;
  };
}
