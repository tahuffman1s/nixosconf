{ config, pkgs, ...}:
let 
in 
{
  programs.steam = {
    enable = true;
  };

  # gamemoded runs system-wide so native games and Flatpak emulators can use it.
  programs.gamemode.enable = true;
}
