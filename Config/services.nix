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
  # Lossless Scaling frame generation (lsfg-vk 2.x from nixpkgs; needs
  # Lossless Scaling owned and installed in Steam). The layer goes into the
  # graphics driver environment, /run/opengl-driver/share/vulkan, which the
  # Vulkan loader always searches, also inside the Steam and AppImage
  # sandboxes. lsfg-vk-ui edits ~/.config/lsfg-vk/conf.toml (version = 2):
  # [global] dll is the "Lossless Scaling" folder when it is not in the
  # default Steam library; a [[profile]] turns on for a game when one of its
  # active_in entries matches the executable, also a Windows .exe under Wine.
  hardware.graphics.extraPackages = [ pkgs.lsfg-vk ];
  environment.systemPackages = [
    pkgs.lsfg-vk-ui
    # The CLI without a second copy of the layer manifest on XDG_DATA_DIRS.
    (pkgs.runCommand "lsfg-vk-cli" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs.lsfg-vk}/bin/lsfg-vk-cli $out/bin/lsfg-vk-cli
    '')
  ];
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