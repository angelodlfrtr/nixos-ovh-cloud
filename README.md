# nixos-ovh-cloud

NixOS base image for OVH Public Cloud (OpenStack), built from a flake.

## Download

Prebuilt images are attached to the
[releases](https://github.com/angelodlfrtr/nixos-ovh-cloud/releases), with a
`SHA256SUMS` file and the `flake.lock` they were built from. Skip to
[Upload to OVH](#upload-to-ovh) and use the downloaded file.

## Build

```sh
nix build .#image
ls result/*.qcow2
```

Requires KVM on the build host (the image is assembled inside a QEMU VM).
On a non-NixOS host, if Nix complains that a system "with features {kvm} is
required", add `system-features = nixos-test benchmark big-parallel kvm` to
`/etc/nix/nix.conf` and restart the Nix daemon.

The qcow2 is compressed (~650 MB).

## Test

```sh
nix flake check -L
```

Boots the real qcow2 in QEMU against a fake OpenStack metadata service
(`tests/boot.nix`) and checks: hostname and root SSH key from metadata,
key-only SSH, `#!` user-data execution, root filesystem growth, no failed
units, and a reboot. Takes well under a minute once the image is built.

## Upload to OVH

With the OpenStack CLI and your OVH `openrc.sh` sourced:

```sh
openstack image create \
  --disk-format qcow2 --container-format bare \
  --private \
  --property hw_disk_bus=virtio \
  --property hw_vif_model=virtio \
  --property hw_qemu_guest_agent=yes \
  --file result/*.qcow2 \
  nixos-26.05
```

`hw_disk_bus=virtio` matters: the bootloader is configured for `/dev/vda`.
The image boots in BIOS mode (OVH default), so do not set
`hw_firmware_type=uefi`.

Then create an instance from the image, with an SSH key:

```sh
openstack server create --image nixos-26.05 --flavor d2-2 \
  --key-name my-key --network Ext-Net my-nixos
ssh root@<ip>
```

## What happens on first boot

- The root partition and filesystem grow to the flavor's disk size.
- Hostname and the SSH public key are fetched from the metadata service
  (`169.254.169.254`); the key is added to `root`'s `authorized_keys`.
- User-data starting with `#!` is executed as a script (once per boot).

The metadata fetch runs at every boot and sshd waits for it. OVH's metadata
service sometimes accepts the connection and never answers, and upstream runs
`wget` without a timeout, so the fetch hangs and takes sshd with it. Each
`wget` is therefore bounded (`--timeout=5 --tries=2` in `modules/ovh.nix`,
against about 1.5 seconds for a whole run when the service answers), with
`TimeoutStartSec = 60` left as a backstop. An unresponsive metadata service
then costs a few seconds of boot instead of sshd, `openstack-init` still ends
successfully, and the instance keeps the key and hostname of the previous
boot.

Boot output goes to the serial port, so `openstack console log show <server>`
is the first place to look if an instance is unreachable.

Cloud-init is not used; this is the upstream nixpkgs OpenStack setup
(`virtualisation/openstack-config.nix`).

## Layout

- `modules/ovh.nix` – runtime config for an OVH instance (`nixosModules.ovh`)
- `modules/image.nix` – qcow2 builder, `system.build.ovhImage` (`nixosModules.image`)
- `configuration.nix` – contents of the base image
- `tests/boot.nix` – VM boot test (`checks.x86_64-linux.boot`)

## Releasing

Tags are `v<nixos release>.<YYYYMMDD>`. CI runs the boot test, then builds the
image and publishes a GitHub release; a tag that does not match the flake's
NixOS release is rejected.

```sh
git tag v26.05.$(date +%Y%m%d) && git push origin --tags
```

## Managing a deployed instance

In the host's own flake, import the runtime module so rebuilds keep the
bootloader / filesystem / metadata setup:

```nix
{
  inputs.ovh.url = "path:/path/to/nixos-ovh-cloud"; # or a git URL
  outputs = { nixpkgs, ovh, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ovh.nixosModules.ovh ./my-host.nix ];
    };
  };
}
```

```sh
nixos-rebuild switch --flake .#my-host --target-host root@<ip>
```
