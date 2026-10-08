{ config, pkgs, ...}:
let 
in 
{
  # `update` in fish runs topgrade. On this system that means:
  #   1. pre_commands: refresh flake.lock in /etc/nixos (owned by the user)
  #   2. system step:  sudo nixos-rebuild switch --upgrade --flake /etc/nixos
  #   3. flatpak step: flatpak update
  # plus whatever else topgrade finds (pipx, rustup, ...).
  programs.topgrade = {
    enable = true;
    settings = {
      misc = {
        assume_yes = true;
        # VSCodium extensions are managed by home-manager, not by the editor.
        disable = [ "vscode" ];
      };
      pre_commands = {
        "Update flake inputs" = "nix flake update --flake /etc/nixos";
      };
      linux = {
        nix_handler = "vanilla";
        nix_arguments = "--flake /etc/nixos";
      };
    };
  };
}
