# nixos-ovh-cloud

NixOS base image for OVH Public Cloud (OpenStack), built from a flake.

## Build

```sh
nix build .#image
ls result/*.qcow2
```

Requires KVM on the build host (the image is assembled inside a QEMU VM).

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

Cloud-init is not used; this is the upstream nixpkgs OpenStack setup
(`virtualisation/openstack-config.nix`).

## Layout

- `modules/ovh.nix` – runtime config for an OVH instance (`nixosModules.ovh`)
- `modules/image.nix` – qcow2 builder, `system.build.ovhImage` (`nixosModules.image`)
- `configuration.nix` – contents of the base image

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
