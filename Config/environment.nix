{ config, pkgs, ...}:
let 
in 
{
  environment.systemPackages = with pkgs; [
     git
     vim
     wget
     kdePackages.partitionmanager
     ffmpeg
     jellyfin
     jellyfin-web
     jellyfin-ffmpeg
     openssl
     linuxKernel.packages.linux_6_15.xone
     inputs.zen-browser.packages.${pkgs.system}.default
  ];
  environment.variables.EDITOR = "vim";
}