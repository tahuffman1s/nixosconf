{ config, pkgs, ...}:
let 
in 
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      alias fetch=fastfetch
      alias swap="sudo nixos-rebuild switch --flake /etc/nixos"
      alias cd=z
      alias flake="codium /etc/nixos/flake.nix"
      alias conf="codium /etc/nixos/configuration.nix"
      alias home="codium /etc/nixos/Home/home.nix"
      alias genConf="sudo nixos-generate-config"
      alias ship="codium ~/.config/starship.toml"
      alias genHardware="sudo nixos-generate-config"
      alias update="nixos-updater update"
      alias flush="nixos-updater flush"
      alias wipeass="journalctl -xe --unit home-manager-$USER"
    '';
  };
}
