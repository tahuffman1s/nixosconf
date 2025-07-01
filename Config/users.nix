{ config, pkgs, ...}:
let 
in 
{
  users.users.travis = {
    isNormalUser = true;
    description = "Travis Huffman";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}