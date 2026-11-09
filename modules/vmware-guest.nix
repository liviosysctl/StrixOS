# VMware guests: make hibernation survive VMware Tools.
#
# After a resume from hibernation the VMCI driver (vmw_vmci) comes back from
# the image, but its state no longer matches the VMware host. As soon as
# vmtoolsd talks to the host over it, the whole guest freezes: no keyboard,
# no console switch, no network. Found 2026-11-09 with test_resume in
# VMware Workstation Pro on Linux, guest kernel 6.18:
#   - vmtoolsd running during hibernation       -> freezes after resume
#   - vmtoolsd stopped, started after resume     -> freezes on start
#   - VMCI unloaded before, loaded fresh after   -> works
#
# So before hibernating, this unit stops vmtoolsd (Conflicts=) and unloads
# VMCI and the drivers that use it. When the sleep target goes away after the
# resume, StopWhenUnneeded stops the unit again, which loads the drivers fresh
# and starts vmtoolsd. If unloading fails, the unit fails, ExecStop never
# runs and vmtoolsd stays off until the next boot instead of freezing.
{ config, lib, pkgs, ... }:

let
  branding = import ../branding.nix;
  vmciModules = [ "vmw_vsock_vmci_transport" "vmw_balloon" "vmw_vmci" ];
  hibernateTargets = [ "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
in
{
  config = lib.mkIf config.virtualisation.vmware.guest.enable {
    systemd.services."${branding.id}-vmware-hibernate" = {
      description = "Unload VMCI and stop VMware Tools around hibernation";
      wantedBy = hibernateTargets;
      before = [ "sleep.target" ];
      after = [ "vmware.service" ];
      conflicts = [ "vmware.service" ];
      unitConfig = {
        StopWhenUnneeded = true;
        ConditionVirtualization = "vmware";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.kmod}/bin/modprobe -r ${lib.concatStringsSep " " vmciModules}";
        ExecStop = [
          "${pkgs.kmod}/bin/modprobe -a ${lib.concatStringsSep " " (lib.reverseList vmciModules)}"
          "${config.systemd.package}/bin/systemctl start --no-block vmware.service"
        ];
      };
    };
  };
}
