{ config, pkgs, inputs, ...}:
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
  ];
  environment.variables.EDITOR = "vim";
}