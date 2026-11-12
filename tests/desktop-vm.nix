# The desktop in a VM: log in through the login of Strix (Quickshell in cage), Hyprland starts as a UWSM session with the
# configuration of Strix and the shell on it, Super Return opens Ghostty, the window border has
# the color of the theme, `strix-theme set janus` changes it while Hyprland runs, the lock screen
# locks and takes the password, Search and the cheat sheet open, the session's theme moves on by
# itself and stays when kept, the theme picker opens and sets the machine's theme through polkit,
# Settings opens at a page.
# Screenshots of each.
#
#   nix build .#tests.desktop -L
#
# Not part of nix flake check: Hyprland renders in software here (minutes without KVM).
{ self, pkgs }:

let
  branding = import ../branding.nix;
  id = branding.id;
  password = "strix-test";
in
pkgs.testers.runNixOSTest {
  name = "${id}-desktop";

  node.specialArgs.distroFlake = self;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/theme.nix
        ../modules/ui.nix
        ../modules/search.nix
        ../modules/desktop.nix
      ];

      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };

      # A plain virtio GPU; Mesa renders in software
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
      # No change by itself during the test; "next" moves it on
      ${id}.desktop.themeCycle = "86400s";
    };

  extraPythonPackages = p: [ p.pillow ];

  testScript = ''
    from PIL import Image

    def border_colors(name):
        """Colors along the row through the middle of the screen, left edge first."""
        machine.screenshot(name)
        image = Image.open(machine.out_dir / f"{name}.png").convert("RGB")
        width, height = image.size
        return ["#%02x%02x%02x" % image.getpixel((x, height // 2)) for x in range(0, 60)]

    def near(a, b):
        """Hyprland blends the one-pixel border a little with its shadow"""
        pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
        pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
        return all(abs(x - y) <= 12 for x, y in zip(pa, pb))

    def expect_border(name, color):
        for _ in range(90):
            if any(near(c, color) for c in border_colors(name)):
                return
            machine.sleep(2)
        raise Exception(f"{name}: no {color} near the left edge: {border_colors(name)}")

    machine.start()
    machine.wait_for_unit("greetd.service")

    greeter = "runuser -u greeter -- env XDG_RUNTIME_DIR=/run/user/$(id -u greeter) qs -c ${id}-greeter ipc --any-display call greeter"

    with subtest("log in through the login of Strix"):
        try:
            machine.wait_until_succeeds(f"{greeter} ready | grep -qx true", timeout=600)
        except Exception:
            import shutil
            machine.screenshot("greeter-stuck")
            shutil.copy(machine.out_dir / "greeter-stuck.png", "greeter-stuck.png")
            for call in ["ready", "state", "error"]:
                print(call, machine.execute(f"{greeter} {call} 2>&1"))
            print(machine.execute("runuser -u greeter -- env XDG_RUNTIME_DIR=/run/user/$(id -u greeter) qs list --all 2>&1"))
            print(machine.execute("runuser -u greeter -- env XDG_RUNTIME_DIR=/run/user/$(id -u greeter) qs log -c ${id}-greeter 2>&1 | tail -n 40"))
            print(machine.execute("journalctl -b --no-pager -t ${id}-greeter | grep -v -e EGL -e GLES -e MESA -e radv | tail -n 40")[1])
            raise
        machine.sleep(5)
        machine.screenshot("greeter")
        # A wrong password is refused
        machine.send_chars("alice\n")
        machine.send_chars("wrong\n")
        machine.wait_until_succeeds(f"{greeter} error | grep -q Wrong", timeout=300)
        machine.screenshot("greeter-wrong")
        machine.wait_until_succeeds(f"{greeter} ready | grep -qx true", timeout=120)
        machine.send_chars("${password}\n")
        machine.wait_until_succeeds("test -s /var/lib/${id}-greeter/last-user", timeout=300)
        machine.succeed("grep -x alice /var/lib/${id}-greeter/last-user")

    run = "/run/user/$(id -u alice)"
    env = f"-u DISPLAY XDG_RUNTIME_DIR={run} WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls {run}/hypr | head -n1) SESSION_SOCKET={run}/${id}/theme.sock"

    def session(method, params="{}"):
        import json
        return json.loads(as_alice(f"${id}-theme session call {method} '{params}'"))

    def border_of(god):
        import json
        return json.loads(machine.succeed(f"${id}-theme show {god}"))["colors"]["border-active"]

    def as_alice(command):
        """Again until it works: Hyprland's socket may not answer in time while it renders in software"""
        return machine.wait_until_succeeds(f"runuser -u alice -- env {env} {command}", timeout=180)

    def alice_until(command, timeout=300):
        machine.wait_until_succeeds(f"runuser -u alice -- env {env} {command}", timeout=timeout)

    def hyprland_log():
        print(machine.execute(f"runuser -u alice -- env {env} qs -c ${id} ipc show 2>&1")[1])
        print(machine.execute(f"runuser -u alice -- env {env} qs list --all 2>&1")[1])
        print(machine.execute(f"tail -n 80 {run}/hypr/*/hyprland.log")[1])
        print(machine.execute("journalctl -b --no-pager -n 80 _UID=$(id -u alice)")[1])

    with subtest("Hyprland reads the configuration of Strix"):
        try:
            machine.wait_until_succeeds(f"ls {run}/hypr/*/.socket.sock", timeout=300)
            alice_until("hyprctl version", timeout=900)
        except Exception:
            hyprland_log()
            raise
        config = as_alice("hyprctl -j getoption general:gaps_out")
        print(config)
        assert "12" in config, config
        binds = as_alice("hyprctl -j binds")
        assert binds.count('"description"') >= 50, binds[:500]
        print(as_alice("hyprctl -j getoption general:col.active_border"))

    with subtest("the shell runs: wallpaper, bar, its IPC targets"):
        machine.wait_for_unit("${id}-shell.service", "alice")
        try:
            alice_until("qs -c ${id} ipc show | grep -q 'target lock'", timeout=180)
        except Exception:
            hyprland_log()
            raise
        targets = as_alice("qs -c ${id} ipc show")
        print(targets)
        for target in ["bar", "lock", "search", "cheatsheet", "notifications"]:
            assert f"target {target}" in targets, target
        machine.wait_for_unit("${id}-search.service", "alice")
        machine.sleep(10)
        machine.screenshot("desktop")
        image = Image.open(machine.out_dir / "desktop.png").convert("RGB")
        colors = len(image.getcolors(1 << 24) or [])
        assert colors > 200, f"the screen has {colors} colors, the wallpaper is missing"

    with subtest("Search and the cheat sheet open"):
        machine.send_key("meta_l-spc")
        try:
            alice_until("qs -c ${id} ipc call search ready | grep -qx true", timeout=300)
        except Exception:
            machine.screenshot("search-stuck")
            for call in ["isOpen", "ready", "text"]:
                print(call, machine.execute(f"runuser -u alice -- env {env} qs -c ${id} ipc call search {call} 2>&1"))
            print(machine.execute(f"runuser -u alice -- env {env} hyprctl -j activewindow 2>&1")[1])
            print(machine.execute(f"runuser -u alice -- env {env} hyprctl -j layers 2>&1")[1][:3000])
            raise
        machine.sleep(3)
        machine.screenshot("search")
        machine.send_chars("term")
        try:
            alice_until("qs -c ${id} ipc call search text | grep -qx term", timeout=120)
        except Exception:
            import shutil
            machine.screenshot("search-typed")
            shutil.copy(machine.out_dir / "search-typed.png", "search-typed.png")
            for call in ["isOpen", "ready", "text"]:
                print(call, machine.execute(f"runuser -u alice -- env {env} qs -c ${id} ipc call search {call} 2>&1"))
            print(machine.execute(f"runuser -u alice -- env {env} hyprctl -j activewindow 2>&1")[1])
            print(machine.execute(f"runuser -u alice -- env {env} hyprctl -j layers 2>&1")[1][:4000])
            print(machine.execute(f"runuser -u alice -- env {env} hyprctl -j devices 2>&1")[1][:2000])
            raise
        machine.sleep(5)
        machine.screenshot("search-term")
        machine.send_key("esc")
        machine.send_key("esc")
        alice_until("qs -c ${id} ipc call search isOpen | grep -qx false", timeout=300)
        machine.send_key("meta_l-k")
        alice_until("qs -c ${id} ipc call cheatsheet isOpen | grep -qx true", timeout=300)
        alice_until("qs -c ${id} ipc call cheatsheet count | grep -qvx 0", timeout=300)
        machine.sleep(5)
        machine.screenshot("cheatsheet")
        machine.send_key("esc")

    with subtest("Super Return opens Ghostty, framed in Saturnus"):
        machine.send_key("meta_l-ret")
        alice_until("hyprctl -j clients | grep -q com.mitchellh.ghostty")
        machine.sleep(10)
        expect_border("saturnus", "#712829")

    with subtest("a theme switch reaches the running desktop"):
        print(machine.succeed("${id}-theme set janus"))
        try:
            machine.wait_until_succeeds(
                f"runuser -u alice -- env {env} hyprctl -j getoption general:col.active_border | grep -qi 3f5149",
                timeout=600,
            )
        except Exception:
            print(as_alice("hyprctl -j getoption general:col.active_border"))
            print(machine.execute(f"cat {run}/${id}/theme/hyprland.lua")[1])
            print(machine.execute("journalctl -b --no-pager _UID=$(id -u alice) -t strix-theme -t ${id}-theme-reload | tail -n 30")[1])
            print(machine.execute("journalctl -b --no-pager --user-unit ${id}-theme-session | tail -n 30")[1])
            raise
        expect_border("janus", "#3f5149")

    with subtest("the session's theme moves on and stays when kept"):
        machine.wait_for_unit("${id}-theme-session.service", "alice")
        state = session("state")
        assert state["theme"] == "janus", state
        assert state["system"] == "janus:dark", state
        state = session("next")
        god = state["theme"]
        assert god != "janus", state
        print(f"the session moved on to {god}")
        expect_border(f"next-{god}", border_of(god))
        machine.succeed("${id}-theme current | grep -x janus:dark")
        state = session("keep", '{"keep": true}')
        assert state["keep"], state
        machine.succeed("grep -q true /home/alice/.local/state/${id}/theme-session.json")

    with subtest("the theme picker opens and sets the machine's theme"):
        machine.send_key("meta_l-ctrl-spc")
        alice_until("qs -c ${id} ipc call theme ready | grep -qx true", timeout=300)
        machine.sleep(3)
        machine.screenshot("picker")
        before = as_alice("qs -c ${id} ipc call theme shown").strip()
        machine.send_key("right")
        alice_until(f"qs -c ${id} ipc call theme shown | grep -vqx {before}", timeout=300)
        machine.sleep(3)
        machine.screenshot("picker-next")
        machine.send_key("esc")
        alice_until("qs -c ${id} ipc call theme isOpen | grep -qx false", timeout=300)
        # The choice by hand goes through pkexec and the polkit rule, without a password
        state = session("set", '{"theme": "mars"}')
        assert state["theme"] == "mars", state
        machine.succeed("${id}-theme current | grep -x mars:dark")
        expect_border("mars", border_of("mars"))
        # Any other pkexec still asks
        machine.fail("runuser -u alice -- pkexec --disable-internal-agent true")

    with subtest("Settings opens at a page"):
        as_alice("${id}-settings hotkeys")
        alice_until("qs -c ${id} ipc call settings page | grep -qx hotkeys", timeout=120)
        machine.sleep(5)
        machine.screenshot("settings-hotkeys")
        as_alice("${id}-settings themes repositories")
        alice_until("qs -c ${id} ipc call settings page | grep -qx themes", timeout=300)
        machine.sleep(5)
        machine.screenshot("settings-themes")
        assert as_alice("qs -c ${id} ipc call settings repositories").strip() == "0"
        as_alice("qs -c ${id} ipc call settings close")

    with subtest("the lock screen locks and takes the password"):
        as_alice("qs -c ${id} ipc call lock lock")
        # Locked for the compositor, and the password field takes keys
        alice_until("qs -c ${id} ipc call lock ready | grep -qx true", timeout=300)
        machine.sleep(5)
        machine.screenshot("lock")
        machine.send_chars("wrong\n")
        alice_until("qs -c ${id} ipc call lock error | grep -q Wrong", timeout=300)
        machine.succeed("journalctl -b | grep -q 'strix-lock.*authentication failure'")
        machine.sleep(3)
        machine.screenshot("lock-wrong")
        assert "true" in as_alice("qs -c ${id} ipc call lock locked")
        alice_until("qs -c ${id} ipc call lock ready | grep -qx true", timeout=120)
        machine.send_chars("${password}\n")
        alice_until("qs -c ${id} ipc call lock locked | grep -qx false", timeout=300)
  '';
}
