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

  # Xbox controllers: xone for wired and the wireless dongle, xpadneo over
  # Bluetooth.
  hardware.xone.enable = true;
  hardware.xpadneo.enable = true;
  hardware.keyboard.qmk.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
