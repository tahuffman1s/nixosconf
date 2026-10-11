{ config, pkgs, ...}:
let 
in 
{
  services.xserver.enable = true;
  services.udev.packages = [ pkgs.via ];
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.flatpak.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  # Lossless Scaling frame generation as a Vulkan layer (needs Lossless
  # Scaling installed in Steam). The layer only looks for Lossless.dll in the
  # default Steam library under ~; a game on another library (the desktop's
  # /mnt/GD1/SteamLibrary) needs its path in the UI's DLL field, which
  # writes [global] dll in ~/.config/lsfg-vk/conf.toml. A game turns it on
  # by matching a [[game]] entry there; under Wine set LSFG_PROCESS=<name>
  # for the game and use that name as the entry's exe.
  services.lsfg-vk = {
    enable = true;
    ui.enable = true;
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}