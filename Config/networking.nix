{ config, pkgs, ...}:
let 
in 
{
  networking.hostName = "nixos"; #
  networking.networkmanager.enable = true;
  # Steam's ports are opened by programs.steam in Config/gaming.nix.
  networking.firewall.allowedTCPPorts = [ 24800 5354 ];
  networking.firewall.allowedUDPPorts = [ 8766 9700 5353 ];
}