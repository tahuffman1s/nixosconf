{
  description = "My Configuration Flake";

  inputs = {
    # Rolling nixpkgs. Mesa, the kernel and Plasma all track this.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager master is the branch that pairs with nixos-unstable.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-photogimp = {
      url = "github:Libadoxon/nix-photo-gimp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rsensor = {
      url = "github:tahuffman1s/rsensor-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kurve-flake = {
      url = "github:tahuffman1s/kdePackages-kurve-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-flatpak, plasma-manager, lsfg-vk-flake, ... }@inputs:
  let
    # Which account the system and home config are for; see user.nix.
    user = import ./user.nix;
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs user; };
      modules = [
        ./configuration.nix
        lsfg-vk-flake.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          # Plasma rewrites files like ~/.gtkrc-2.0 at every login; move them
          # aside instead of failing on "file in the way", and replace the
          # previous backup each time instead of refusing to clobber it.
          home-manager.backupFileExtension = "hm-backup";
          home-manager.overwriteBackup = true;
          home-manager.extraSpecialArgs = { inherit inputs user; };
          home-manager.users.${user.name}.imports = [
            ./Home/home.nix
            plasma-manager.homeModules.plasma-manager
            nix-flatpak.homeManagerModules.nix-flatpak
          ];
        }
      ];
    };
  };
}
