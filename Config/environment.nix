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
     spotifyd
     openssl
     linuxKernel.packages.linux_6_15.xone
     python312Packages.pip
     python312Packages.pillow
     python312Packages.patool
     python312Packages.tkinter
     python312Packages.pyinstaller
     python312Packages.ttkbootstrap
     python312Full
     unzip
     p7zip
     pipx
  ];
  environment.variables = { 
    EDITOR = "vim";
    LSFG_DLL_PATH = "/mnt/GD1/SteamLibrary/steamapps/common/Lossless Scaling/Lossless.dll";
  };
}