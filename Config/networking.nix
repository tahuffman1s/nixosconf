{ config, pkgs, ...}:
let 
in 
{
  networking.hostName = "nixos"; #
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 24800 27015 27036 57621 5354 ];
  networking.firewall.allowedUDPPorts = [ 8766 9700 5353 ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 27015; to = 27016; }
    { from = 27031; to = 27036; }
  ];
}