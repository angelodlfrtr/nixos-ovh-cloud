{ pkgs, ... }:
{
  # Contents of the base image. Keep it small: machine-specific configuration
  # belongs in the flake of the deployed host (importing `nixosModules.ovh`).

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
  ];

  time.timeZone = "UTC";

  system.stateVersion = "26.05";
}
