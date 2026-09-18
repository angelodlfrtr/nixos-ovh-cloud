# Boots the real qcow2 (plus the test driver backdoor) against a fake
# OpenStack metadata service, the same way nixpkgs tests its own image.
{
  nixpkgs,
  pkgs,
  baseSystem,
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (import "${nixpkgs}/nixos/lib/testing-python.nix" { inherit system pkgs; }) makeTest;
  inherit (import "${nixpkgs}/nixos/tests/common/ec2.nix" { inherit makeTest pkgs; }) makeEc2Test;

  imageCfg =
    (baseSystem.extendModules {
      modules = [ "${nixpkgs}/nixos/modules/testing/test-instrumentation.nix" ];
    }).config;

  sshKeys = import "${nixpkgs}/nixos/tests/ssh-keys.nix" pkgs;
  privateKey = pkgs.writeText "private-key" sshKeys.snakeOilPrivateKey.text;
in
makeEc2Test {
  name = "ovh-image-boot";
  image = "${imageCfg.system.build.ovhImage}/${imageCfg.image.fileName}";
  hostname = "ovh-test";
  sshPublicKey = sshKeys.snakeOilPublicKey;
  userData = ''
    #!/bin/sh
    echo hello-from-userdata > /root/userdata-ran
  '';
  script = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")

    with subtest("hostname comes from the metadata service"):
        assert machine.succeed("hostname").strip() == "ovh-test"

    with subtest("metadata SSH key is authorized for root, and only that key"):
        # `ssh -n`: stdin here is the test driver's control channel; letting
        # ssh touch it intermittently hangs the driver.
        machine.succeed("mkdir -p ~/.ssh")
        machine.succeed(
            "ssh-keyscan -t ed25519 localhost 2>/dev/null > ~/.ssh/known_hosts"
        )
        machine.fail("ssh -n -o BatchMode=yes localhost exit")
        machine.copy_from_host_via_shell("${privateKey}", "~/.ssh/id_ed25519")
        machine.succeed("chmod 600 ~/.ssh/id_ed25519")
        machine.succeed("ssh -n -o BatchMode=yes localhost exit")

    with subtest("password authentication is disabled"):
        machine.succeed("grep -qx 'PasswordAuthentication no' /etc/ssh/sshd_config")
        machine.succeed("grep -qx 'KbdInteractiveAuthentication no' /etc/ssh/sshd_config")

    with subtest("shebang user-data is executed"):
        machine.wait_for_file("/root/userdata-ran")
        assert "hello-from-userdata" in machine.succeed("cat /root/userdata-ran")

    with subtest("root filesystem grows to the disk size"):
        # The test harness resizes the disk to 10G.
        size_mb = int(machine.succeed("df -BM --output=size / | tail -1").strip().rstrip("M"))
        assert size_mb > 9000, f"root fs is only {size_mb}M"

    with subtest("no failed units"):
        machine.wait_for_unit("amazon-init.service")
        failed = machine.succeed("systemctl --failed --no-legend").strip()
        assert failed == "", failed

    with subtest("survives a reboot"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("sshd.service")
        assert machine.succeed("hostname").strip() == "ovh-test"
  '';
}
