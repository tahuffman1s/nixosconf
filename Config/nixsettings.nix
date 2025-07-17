{ config, pkgs, ...}:
let 
in 
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  programs = {
      appimage = {
        enable = true;
        binfmt = true;
        package = pkgs.appimage-run.override {
          extraPkgs = pkgs: [ pkgs.xorg.libxshmfence ];
        };
      };
  };
}