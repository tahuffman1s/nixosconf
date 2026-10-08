{ config, pkgs, user, ...}:
let 
in 
{
  home.username = user.name;
  home.homeDirectory = "/home/${user.name}";
  home.enableNixpkgsReleaseCheck = false;
}