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
  # Scaling installed in Steam; the layer finds Lossless.dll through Steam's
  # library list). The UI edits ~/.config/lsfg-vk/conf.toml per game.
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