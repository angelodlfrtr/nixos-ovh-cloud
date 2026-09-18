{ lib, modulesPath, ... }:
{
  # OVH Public Cloud is OpenStack: root fs by label with auto-resize, grub on
  # /dev/vda, serial console, sshd, and root's SSH key + hostname fetched from
  # the metadata service (169.254.169.254) on first boot.
  imports = [ "${modulesPath}/virtualisation/openstack-config.nix" ];

  # amazon-init runs user-data starting with `#!` as a script (OVH
  # "post-installation script"). Its other mode (user-data as a channel-based
  # configuration.nix) does not apply to a flake-built system without channels.
  virtualisation.amazon-init.enable = lib.mkDefault true;

  services.qemuGuest.enable = lib.mkDefault true;

  # Public interface is configured by DHCP on Ext-Net.
  networking.useDHCP = lib.mkDefault true;
}
