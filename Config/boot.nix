{ config, pkgs, ...}:
let 
in 
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.consoleMode = "max"; 
  boot.kernelPackages = pkgs.linuxPackages_latest;
}