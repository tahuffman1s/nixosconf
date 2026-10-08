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
     openssl
     python3
     python3Packages.pip
     python3Packages.pillow
     python3Packages.patool
     python3Packages.tkinter
     python3Packages.pyinstaller
     python3Packages.ttkbootstrap
     unzip
     p7zip
     pipx
     # Bazaar: Flathub-focused app store, replaces Discover.
     bazaar
  ];

  # Discover is only pulled in because flatpak is enabled; Bazaar takes its place.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  environment.variables = { 
    EDITOR = "vim";
    LSFG_DLL_PATH = "/mnt/GD1/SteamLibrary/steamapps/common/Lossless Scaling/Lossless.dll";
  };
}
