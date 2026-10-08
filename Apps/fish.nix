{ config, pkgs, ...}:
let 
in 
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      alias fetch=fastfetch
      alias swap="rm ~/.gtkrc-2.0; sudo nixos-rebuild switch --flake /etc/nixos"
      alias cd=z
      alias flake="codium /etc/nixos/flake.nix"
      alias conf="codium /etc/nixos/configuration.nix"
      alias home="codium /etc/nixos/Home/home.nix"
      alias genConf="sudo nixos-generate-config"
      alias ship="codium ~/.config/starship.toml"
      alias genHardware="sudo nixos-generate-config"
      alias update="topgrade"
      alias wipeass="journalctl -xe --unit home-manager-$USER"
    '';
  };
}
