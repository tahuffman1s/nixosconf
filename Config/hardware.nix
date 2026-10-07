{ config, pkgs, ...}:
let 
in 
{
  # Mesa (OpenGL/Vulkan) from nixos-unstable, plus the 32-bit libraries that
  # Steam and Proton need. No proprietary NVIDIA driver.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.xone.enable = true;
  hardware.keyboard.qmk.enable = true;

  # Solaar and its udev rules for Logitech receivers.
  hardware.logitech.wireless.enable = true;
  programs.solaar.enable = true;
}
