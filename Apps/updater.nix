{ config, pkgs, ...}:
let 
  nixos-updater = pkgs.callPackage ./updater { };
in 
{
  # The updater app: start menu entry, icon, and the polkit action that lets
  # its privileged helper run nixos-rebuild and the garbage collector.
  environment.systemPackages = [ nixos-updater ];
}
