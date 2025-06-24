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
      alias flake="sudo code /etc/nixos/flake.nix"
      alias conf="sudo code /etc/nixos/configuration.nix"
      alias home="sudo code /etc/nixos/home.nix"
      alias genConf="sudo nixos-generate-config"
    '';
  };
  
  services.flatpak.update.auto.enable = true;
  services.flatpak.packages = [
    "io.github.input_leap.input-leap"
    "com.protonvpn.www"
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
