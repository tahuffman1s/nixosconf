{ config, pkgs, inputs, ...}:
let 
in 
{
  # Native packages only. Everything with a Flathub build lives in
  # Apps/flatpaks.nix instead.
  home.packages = with pkgs; [
    fastfetch
    mangohud
    gamescope
    vulkan-tools
    corefonts
    vista-fonts
    nerd-fonts.fira-mono
    dracula-theme
    via
    spotify-qt   # not on Flathub
    shipwright   # not on Flathub
    inputs.rsensor.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];  
}
