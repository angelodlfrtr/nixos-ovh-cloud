{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/image/file-options.nix" ];

  image.extension = "qcow2";
  system.nixos.tags = [ "ovh" ];

  system.build.image = config.system.build.ovhImage;
  system.build.ovhImage = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;
    inherit (config.image) baseName;
    # Compressed: ~3x smaller upload, Glance/Nova read it transparently.
    format = "qcow2-compressed";
    # BIOS boot, matching `openstack.efi = false` (OVH default firmware).
    partitionTableType = "legacy";
    # The root partition is grown to the flavor's disk size on first boot.
    additionalSpace = "1024M";
    # Flake-based system: no channel, no /etc/nixos/configuration.nix.
    copyChannel = false;
  };
}
