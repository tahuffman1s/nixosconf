{
  description = "My Configuration Flake";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-photogimp = {
      url = "github:Libadoxon/nix-photo-gimp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsensor = {
      url = "github:tahuffman1s/rsensor-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    durdraw = {
      url = "github:tahuffman1s/durdraw-flake";
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
  
  outputs = { self, nixpkgs, home-manager, nix-flatpak, plasma-manager, durdraw, lsfg-vk-flake, kurve-flake, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        lsfg-vk-flake.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.travis.imports = [
            ./Home/home.nix
            plasma-manager.homeManagerModules.plasma-manager
            durdraw.homeManagerModules.default
            nix-flatpak.homeManagerModules.nix-flatpak
          ];
        }
      ];
    };
  };
}
