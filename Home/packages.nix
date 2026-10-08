{ config, pkgs, inputs, ...}:
let 
in 
{
  # Native packages only. Desktop apps live in Apps/flatpaks.nix instead.
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
    inputs.rsensor.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];  
}
