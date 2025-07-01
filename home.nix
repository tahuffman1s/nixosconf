{ config, pkgs, ... }:
let 
in 
{
  imports = [
    ./Apps/git.nix
    ./Apps/starship.nix
    ./Apps/kitty.nix
    ./Apps/fish.nix
    ./Apps/zoxide.nix
    ./Apps/flatpaks.nix
    ./Apps/vscodium.nix
    ./Theme/plasma.nix
    ./Theme/gtk.nix
  ];

  home.username = "travis";
  home.homeDirectory = "/home/travis";
  home.enableNixpkgsReleaseCheck = false;

  home.packages = with pkgs; [
    fastfetch
    signal-desktop
    mangohud
    gamemode
    gamescope
    qbittorrent
    fooyin
    handbrake
    freetube
    corefonts
    vistafonts
    libreoffice
    makemkv
    vlc
    jellyfin-media-player
    dracula-theme
    nerd-fonts.fira-mono
    kdePackages.breeze-gtk
  ];  

  home.stateVersion = "25.05";
}
