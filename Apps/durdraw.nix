{ config, pkgs, ...}:
let 
in 
{
  programs.durdraw = {
    enable = true;
    settings = {
      Main = {
        color-mode = 256;           # Color mode (16, 256, or truecolor)
        cursor-mode = "underscore"; # Cursor style
        scroll-colors = true;       # Enable color scrolling
        auto-save = true;           # Auto-save files
      };
      Theme = {
        theme-16 = "~/.durdraw/themes/custom-16.dtheme.ini";
        theme-256 = "~/.durdraw/themes/custom-256.dtheme.ini";
      };
      Keys = {
        # Custom key bindings
        quit = "q";
        save = "s";
      };
    };
  };
}