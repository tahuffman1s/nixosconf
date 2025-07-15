{ config, pkgs, ...}:
let 
in 
{
  hardware.xone.enable = true;
  hardware.keyboard.qmk.enable = true;
}