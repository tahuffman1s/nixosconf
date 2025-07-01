{ config, pkgs, ...}:
let 
in 
{
  programs.kitty = {
    enable = true;
    themeFile = "Dracula";
    settings = {
      confirm_os_window_close = 0; 
      font_size = 12;
      font_family = "FiraMono Nerd Font Mono";
      background_opacity = 0.7;
    };
  };
}