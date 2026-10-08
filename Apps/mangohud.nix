{ config, pkgs, ...}:
let 
in 
{
  # Overlay is hidden by default; Right Shift + F12 toggles it. Run a game
  # with `mangohud %command%` in its Steam launch options, or turn it on for
  # everything in Steam's settings.
  programs.mangohud = {
    enable = true;
    settings = {
      no_display = true;
      toggle_hud = "Shift_R+F12";
      position = "top-left";
      font_size = 20;
      fps = true;
      frametime = true;
      frame_timing = true;
      gpu_stats = true;
      gpu_temp = true;
      gpu_power = true;
      vram = true;
      cpu_stats = true;
      cpu_temp = true;
      ram = true;
      gamemode = true;
      vulkan_driver = true;
    };
  };
}
