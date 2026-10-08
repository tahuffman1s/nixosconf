{ config, pkgs, user, ...}:
let 
in 
{
  users.users.${user.name} = {
    isNormalUser = true;
    description = user.fullName;
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.wallpaper-engine-plugin
    ];
  };
}