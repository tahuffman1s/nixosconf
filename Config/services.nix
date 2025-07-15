{ config, pkgs, ...}:
let 
in 
{
  services.xserver.enable = true;
  services.udev.packages = [ pkgs.via ];
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.flatpak.enable = true;
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
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
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
}