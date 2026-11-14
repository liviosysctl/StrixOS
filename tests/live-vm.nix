# The live session of the ISO in a VM: greetd logs nixos in without asking, Hyprland starts, and the
# installer's window is open right away with its back end answering. Closed, the card on the desktop
# is there and the window opens again. Screenshots of both.
#
#   nix build .#tests.live -L
#
# Not part of nix flake check: Hyprland renders in software here (minutes without KVM).
{ self, pkgs }:

let
  branding = import ../branding.nix;
  id = branding.id;
in
pkgs.testers.runNixOSTest {
  name = "${id}-live";

  node.specialArgs.distroFlake = self;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../iso/options.nix
        ../iso/live.nix
        ../modules/theme.nix
      ];

      # As on the ISO (installation-device.nix): the live user, sudo without a password
      users.users.nixos = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "video" ];
        initialHashedPassword = "";
      };
      security.sudo.wheelNeedsPassword = false;
      networking.networkmanager.enable = true;

      virtualisation.qemu.options = [
        "-vga none"
        "-device virtio-gpu-pci,xres=1280,yres=800"
      ];
      virtualisation.memorySize = 3072;
      virtualisation.cores = 2;
      environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE = "1";

      # Software rendering without KVM: Hyprland needs far longer than the 30 seconds UWSM waits
      systemd.user.services."wayland-wm@" = {
        overrideStrategy = "asDropin";
        serviceConfig.TimeoutStartSec = 900;
      };
      systemd.user.services.wayland-session-waitenv = {
        overrideStrategy = "asDropin";
        serviceConfig.TimeoutStartSec = 900;
      };
    };

  testScript = ''
    import shutil

    machine.start()
    run = "/run/user/1000"
    env = f"-u DISPLAY XDG_RUNTIME_DIR={run} WAYLAND_DISPLAY=wayland-1"
    ipc = f"runuser -u nixos -- env {env} qs -c ${id}-installer ipc call installer"

    def logs():
        print(machine.execute(f"runuser -u nixos -- env {env} qs log -c ${id}-installer 2>&1 | tail -n 60")[1])
        print(machine.execute("journalctl -b --no-pager -n 60 _UID=1000 | grep -v -e EGL -e MESA")[1])

    with subtest("logged in at once, the installer's window open"):
        try:
            machine.wait_until_succeeds(f"{ipc} isOpen | grep -qx true", timeout=900)
            machine.wait_until_succeeds(f"test -S {run}/${id}/install.sock", timeout=120)
        except Exception:
            machine.screenshot("live-stuck")
            shutil.copy(machine.out_dir / "live-stuck.png", "live-stuck.png")
            logs()
            raise
        # Hyprland renders in software here: let the window finish fading in
        machine.sleep(60)
        machine.screenshot("installer")

    with subtest("no QML errors in the window"):
        out = machine.execute(f"runuser -u nixos -- env {env} qs log -c ${id}-installer 2>&1")[1]
        print(out[-3000:])
        bad = [l for l in out.splitlines() if any(w in l for w in ("ReferenceError", "TypeError", "is not a type", "is not defined", "Cannot assign"))]
        assert not bad, bad

    with subtest("closed, the card opens it again"):
        machine.succeed(f"{ipc} close")
        machine.wait_until_succeeds(f"{ipc} isOpen | grep -qx false", timeout=60)
        machine.sleep(60)
        machine.screenshot("launcher")
        machine.succeed(f"{ipc} open")
        machine.wait_until_succeeds(f"{ipc} isOpen | grep -qx true", timeout=60)
  '';
}
