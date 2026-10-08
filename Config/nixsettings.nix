{ config, pkgs, user, ...}:
let 
in 
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # /etc/nixos is a symlink to the user's checkout. Root runs nixos-rebuild
  # (and topgrade runs it through sudo), and nix refuses to read a git repo
  # owned by someone else unless it is listed here.
  programs.git = {
    enable = true;
    config.safe.directory = [
      "/etc/nixos"
      "/home/${user.name}/nixosconf"
    ];
  };
  programs = {
      appimage = {
        enable = true;
        binfmt = true;
        package = pkgs.appimage-run.override {
          extraPkgs = pkgs: [ pkgs.libxshmfence ];
        };
      };
  };
}