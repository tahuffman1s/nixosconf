{ config, pkgs, ... }:

{
  home.username = "travis";
  home.homeDirectory = "/home/travis";

  home.packages = with pkgs; [
    fastfetch
    signal-desktop
    mangohud
    gamemode
    gamescope
    kitty
    qbittorrent
    fooyin
    handbrake
    freetube
    calibre
    filebot
    makemkv
    vlc
    python313
    python313Packages.pip
    python313Packages.pipx
    python313Packages.cryptography
    jellyfin-media-player
  ];

  programs.git = {
    enable = true;
    userName = "Travis Huffman";
    userEmail = "huffmantravis57@protonmail.com";
  };

  programs.starship = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      alias fetch=fastfetch
      alias update="sudo nixos-rebuild switch"
      alias cd=z
      alias flake="code /etc/nixos/flake.nix"
      alias conf="code /etc/nixos/configuration.nix"
      alias home="code /etc/nixos/home.nix"
      alias genConf="sudo nixos-generate-config"
    '';
  };
  
  services.flatpak.update.auto.enable = true;
  services.flatpak.packages = [
    "io.github.input_leap.input-leap"
    "com.protonvpn.www"
    "org.gtk.Gtk3theme.Breeze"
  ];

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      vscodevim.vim
    ];
  };
  
  home.stateVersion = "25.05";
}
