# Intel processors are kept below their heat limits by thermald, which slows them down early and a
# little instead of late and a lot: quieter fans on a laptop, no sudden drops. Other processors
# skip it (the condition), they have nothing for it to do.
{ lib, pkgs, ... }:

{
  services.thermald.enable = lib.mkDefault true;
  systemd.services.thermald.serviceConfig.ExecCondition =
    "${lib.getExe pkgs.gnugrep} -q GenuineIntel /proc/cpuinfo";
}
