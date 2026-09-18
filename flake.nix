{
  description = "NixOS base image for OVH Public Cloud (OpenStack)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosModules = {
        # Runtime configuration of an OVH instance. Import this in the
        # configuration of machines deployed from the image.
        ovh = ./modules/ovh.nix;
        # Adds `system.build.ovhImage` (qcow2).
        image = ./modules/image.nix;
      };

      nixosConfigurations.ovh-base = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.ovh
          self.nixosModules.image
          ./configuration.nix
        ];
      };

      packages.${system} = rec {
        image = self.nixosConfigurations.ovh-base.config.system.build.ovhImage;
        default = image;
      };

      checks.${system}.boot = import ./tests/boot.nix {
        inherit nixpkgs;
        pkgs = nixpkgs.legacyPackages.${system};
        baseSystem = self.nixosConfigurations.ovh-base;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
