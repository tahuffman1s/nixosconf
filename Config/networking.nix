{ config, pkgs, ...}:
let 
in 
{
  networking.hostName = "nixos"; #
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 24800 ];
}