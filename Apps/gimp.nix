{ config, pkgs, inputs, ...}:
let 
  # Pinned to a commit instead of the moving master.zip, which silently
  # breaks the hash whenever upstream pushes.
  theme = pkgs.fetchFromGitHub {
    owner = "dracula";
    repo = "gimp";
    rev = "c42e1b525b382c3485a7beef898b14ea03556593";
    hash = "sha256-R7VQZs5yCRa529L4LwpFQP+L5h9tp8Iz0zr/+2HmmYA=";
  };
in 
{
  home.packages = with pkgs; [
    inputs.nix-photogimp.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
  home.file = {
    ".config/PhotoGIMP/3.0/themes/Dracula" = {source ="${theme}/Dracula";};
  };
}
