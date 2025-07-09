{ config, pkgs, ... }:
let 
in 
{
  imports = [
   ./packages.nix
   ./settings.nix
   ../Apps/git.nix
   ../Apps/starship.nix
   ../Apps/kitty.nix
   ../Apps/fish.nix
   ../Apps/zoxide.nix
   ../Apps/flatpaks.nix
   ../Apps/vscodium.nix
   ../Apps/gimp.nix
   ../Apps/firefox.nix
   ../Apps/durdraw.nix
   ../Theme/plasma.nix
   ../Theme/gtk.nix
  ];

  home.stateVersion = "25.05";
}
