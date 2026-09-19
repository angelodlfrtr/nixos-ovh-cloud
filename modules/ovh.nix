{ lib, modulesPath, ... }:
let
  # Same script as upstream, whose wget options are a `let` binding of
  # openstack-config.nix rather than an option, so the only way to add
  # timeouts is to generate the script again.
  #
  # Each fetch tolerates failure (`|| true`), so with a bound on wget the
  # unit now ends successfully on a stalled metadata service instead of
  # being killed: the boot keeps the metadata of the previous boot.
  # A whole run takes about 1.5s when the service answers normally.
  metadataFetcher = import "${modulesPath}/virtualisation/openstack-metadata-fetcher.nix" {
    targetRoot = "/";
    wgetExtraOptions = "--retry-connrefused --timeout=5 --tries=2 --waitretry=1";
  };
in
{
  # OVH Public Cloud is OpenStack: root fs by label with auto-resize, grub on
  # /dev/vda, serial console, sshd, and root's SSH key + hostname fetched from
  # the metadata service (169.254.169.254) on first boot.
  imports = [ "${modulesPath}/virtualisation/openstack-config.nix" ];

  # amazon-init runs user-data starting with `#!` as a script (OVH
  # "post-installation script"). Its other mode (user-data as a channel-based
  # configuration.nix) does not apply to a flake-built system without channels.
  virtualisation.amazon-init.enable = lib.mkDefault true;

  # sshd is ordered after the metadata fetch (openstack-init -> apply-ec2-data
  # -> sshd-keygen -> sshd), and upstream runs wget without a timeout: when
  # the metadata service accepts the connection but never answers (seen on
  # OVH, on the first boot and on later ones), the fetch hangs and takes sshd
  # with it.
  #
  # Bounding wget is what actually keeps the boot going; TimeoutStartSec is
  # the backstop for anything the retries do not cover. It stays at a minute,
  # comfortably above the ~44s the four fetches can take at worst.
  systemd.services.openstack-init = {
    script = lib.mkForce metadataFetcher;
    serviceConfig.TimeoutStartSec = lib.mkDefault 60;
  };

  # Serial port as primary console (last `console=` wins), like other cloud
  # images: boot output shows up in `openstack console log show`. tty1 (set
  # upstream) still gets a login prompt in the VNC console.
  boot.kernelParams = lib.mkAfter [ "console=ttyS0,115200" ];

  # Key-only SSH (upstream already disables PasswordAuthentication).
  services.openssh.settings.KbdInteractiveAuthentication = lib.mkDefault false;

  services.qemuGuest.enable = lib.mkDefault true;

  # Public interface is configured by DHCP on Ext-Net.
  networking.useDHCP = lib.mkDefault true;
}
