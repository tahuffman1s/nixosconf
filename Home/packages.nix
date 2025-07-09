{ config, pkgs, inputs, ...}:
let 
in 
{
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
    libreoffice-qt6-fresh
    obsidian
    inputs.rsensor.packages.${pkgs.system}.default
    inputs.zen-browser.packages.${pkgs.system}.default
  ];  
}