# The installer core on an empty disk, then the installed disk booted on its
# own: passphrase, login, swap, /etc/nixos.
#
#   nix build .#tests.install -L
#
# Not part of nix flake check: two VM boots and a full install take 15 to 30
# minutes with KVM. CI runs it every night (.github/workflows/install-test.yml).
#
# Test VMs have no internet, so nixos-install must find every store path
# locally. The installed system is therefore made exactly predictable (fixed
# answers, a fixed hardware.nix, the expected machine.nix) and built here in
# advance, and the installer VM gets it in its store. If the installer writes
# anything else, it would have to build or download and the test fails; the
# test script then shows the difference.
#
# Needs a clean, committed tree: the installer writes a flake.lock that points
# at this commit (machine-lock), which only exists with self.rev.
{ self, pkgs }:

let
  inherit (pkgs) lib;
  branding = import ../branding.nix;
  id = branding.id;
  system = pkgs.stdenv.hostPlatform.system;

  installer = self.packages.${system}.installer;
  machineLock =
    self.packages.${system}.machine-lock
      or (throw "tests.install needs a clean, committed tree with flake.lock (no machine-lock without self.rev)");

  # Memory of the installer VM. The swap file in machine.nix depends on it:
  # with hibernation it is memory + 1 GiB, so 5 GiB here gives "6G".
  installerMemory = 5120;

  # What the front end would write for these answers
  # builtins.toFile instead of writeText: the expected system imports these
  # files during evaluation, which a derivation could only do as IFD.
  answers = builtins.toFile "answers.json" (
    builtins.toJSON {
      hostName = "${id}-test";
      timeZone = "Europe/Zurich";
      locale = "en_US.UTF-8";
      keyboard = "ch";
      user = {
        name = "test";
        fullName = "Test User";
      };
      disk = "/dev/vda";
      encrypt = true;
      hibernation = true;
    }
  );
  password = "testtest";

  # Stands in for the hardware.nix of nixos-generate-config. The installer
  # copies it to /etc/nixos (--hardware-nix), the expected system below uses
  # the same file, so both are the same derivation.
  hardwareNix = builtins.toFile "hardware.nix" ''
    { lib, modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        # Lets the test driver control the installed system after the reboot
        (modulesPath + "/testing/test-instrumentation.nix")
      ];
      nixpkgs.hostPlatform = "${system}";
      # Without the splash the passphrase prompt reaches the serial console,
      # where the test driver types it
      ${id}.boot.splash.enable = false;
    }
  '';

  # What the installer must write as machine.nix. The test compares it with
  # the written file, so the rendering is tested too.
  machineNix = builtins.toFile "machine.nix" (
    builtins.replaceStrings
      [ "@distroId@" "@stateVersion@" ]
      [ id lib.trivial.release ]
      (builtins.readFile ./fixtures/machine.nix)
  );

  # The system the installer will build, from the same files as /etc/nixos
  template = ../templates/machine;
  expected = self.lib.mkSystem (
    {
      modules = [
        hardwareNix
        machineNix
      ];
    }
    # Only main has the Store and its apps.json
    // lib.optionalAttrs (builtins.pathExists (template + "/apps.json")) {
      apps = template + "/apps.json";
    }
  );
  expectedDrv = builtins.unsafeDiscardStringContext expected.config.system.build.toplevel.drvPath;

  # Both VMs use the same disk: the installer writes it, the target boots it.
  # Sparse, so the 64 GiB cost nothing until written.
  commonConfig = {
    virtualisation.diskImage = "./target.qcow2";
    virtualisation.diskSize = 64 * 1024;
  };
in
pkgs.testers.runNixOSTest {
  name = "${id}-install";

  nodes.installer =
    { lib, ... }:
    {
      imports = [ commonConfig ];

      # The installer runs from its own small root disk (vdb), so the target
      # disk is /dev/vda during and after the installation
      virtualisation.emptyDiskImages = [ 2048 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;

      virtualisation.useEFIBoot = true;
      virtualisation.memorySize = installerMemory;
      virtualisation.cores = 2;

      environment.systemPackages = [
        installer
        self.inputs.disko.packages.${system}.disko
      ];
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # Everything nixos-install needs, already in the store
      virtualisation.additionalPaths = [
        expected.config.system.build.toplevel
        expected.config.system.build.destroyFormatMount
        machineLock
        self.outPath
      ]
      ++ map (input: input.outPath) (lib.attrValues self.inputs);

      nix.settings = {
        # The system and the small derivations it is made of (the toplevel,
        # kernel modules, /etc ...) say allowSubstitutes = false, so Nix would
        # rebuild them instead of taking them from the store of this VM,
        # which needs stdenv and downloads. On the ISO that just works with
        # the network, here they have to come from the store.
        always-allow-substitutes = true;
        substituters = lib.mkForce [ ];
        hashed-mirrors = null;
        connect-timeout = 1;
        flake-registry = "";
      };
    };

  nodes.target = {
    imports = [ commonConfig ];
    # Boots from the installed disk with its own boot loader. The settings
    # below only satisfy the test framework, this configuration never runs.
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
    virtualisation.useDefaultFilesystems = false;
    virtualisation.efi.keepVariables = false;
    virtualisation.memorySize = 2048;
    virtualisation.fileSystems."/" = {
      device = "/dev/disk/by-label/this-is-not-real-and-will-never-be-used";
      fsType = "ext4";
    };
  };

  testScript = ''
    stage = "/run/${id}-install/etc-nixos"

    installer.start()
    installer.wait_for_unit("multi-user.target")

    with subtest("install from the answers file"):
        installer.succeed(
            "install -d -m 0700 /run/${id}-install",
            "printf '%s\\n' ${password} > /run/${id}-install/user.pass",
            "printf '%s' ${password} > /tmp/${id}-luks.key",
        )
        status, _ = installer.execute(
            "${id}-install --core --answers ${answers} --hardware-nix ${hardwareNix} --no-unmount >&2"
        )
        if status != 0:
            # Most likely the installer built a different system than the
            # one prepared in the store. Show where it differs.
            installer.execute(f"diff -u ${machineNix} {stage}/machine.nix >&2")
            installer.execute(f"nix eval --raw {stage}#nixosConfigurations.${id}.config.system.build.toplevel.drvPath >&2; echo >&2")
            installer.execute("echo 'expected: ${expectedDrv}' >&2")
            installer.execute("tail -n 60 /tmp/${id}-install.log >&2")
            raise Exception(f"the installer failed with exit code {status}")

    with subtest("the files in /etc/nixos"):
        installer.succeed("diff -u ${machineNix} /mnt/etc/nixos/machine.nix >&2")
        installer.succeed("cmp ${machineLock} /mnt/etc/nixos/flake.lock")
        installer.succeed("test \"$(stat -c '%U %a' /mnt/etc/nixos/machine.nix)\" = 'root 644'")

    with subtest("no secret is left behind"):
        installer.fail("grep -rqs ${password} /mnt/etc/nixos /mnt/var/log/${id}-install.log")
        installer.fail("test -e /run/${id}-install/user.pass")
        installer.fail("test -e /tmp/${id}-luks.key")

    with subtest("release the disk"):
        installer.succeed(
            "swapoff -a",
            "umount -R /mnt",
            "cryptsetup close cryptsystem",
            "sync",
        )
        installer.shutdown()

    # Same disk, now booted from its own boot loader
    target.state_dir = installer.state_dir
    target.start()

    with subtest("the passphrase opens the disk"):
        target.wait_for_console_text("Please enter passphrase")
        target.send_console("${password}\n")
        target.wait_for_unit("multi-user.target")

    with subtest("the installed system"):
        target.succeed("test \"$(hostname)\" = ${id}-test")
        target.succeed("getent shadow test | cut -d: -f2 | grep -q '^\\$'")
        target.succeed("swapon --show=NAME --noheadings | grep -qx /swap/swapfile")
        target.succeed("findmnt -no OPTIONS /home | grep -q subvol=/@home")
        target.succeed("test -f /etc/nixos/flake.lock")
        target.succeed("test \"$(readlink -f /run/current-system)\" = ${expected.config.system.build.toplevel}")

    target.shutdown()
  '';
}
