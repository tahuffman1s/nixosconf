{ config, pkgs, ...}:
let 
in 
{
  home.username = "travis";
  home.homeDirectory = "/home/travis";
  home.enableNixpkgsReleaseCheck = false;
}