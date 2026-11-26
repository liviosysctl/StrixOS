# Firmware updates of the machine and its devices.
{ lib, ... }:

{
  # Firmware of the machine and its devices from the LVFS. <id>-update says when there is new
  # firmware; `fwupdmgr update` installs it.
  services.fwupd.enable = lib.mkDefault true;
  # The daemon starts when it is asked and goes after five idle minutes. One that took longer
  # than half a second to start would otherwise stay for good, as it does on slower laptops
  services.fwupd.daemonSettings.IdleInhibitStartupThreshold = lib.mkDefault 0;
}
