{ config, pkgs, inputs, ...}:
let 
  theme = pkgs.fetchzip {
    url = "https://github.com/dracula/gimp/archive/master.zip";
    sha256 = "sha256-cXHWUJObcF6zLoavglU7xkXF0+4FI74KzmrAtDp6PFE=";
  };
in 
{
  home.packages = with pkgs; [
    inputs.nix-photogimp.packages.${pkgs.system}.default
  ];
  home.file = {
    ".config/PhotoGIMP/3.0/themes/Dracula" = {source ="${theme}";};
  };
}