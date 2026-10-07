{ config, pkgs, lib, inputs, ...}:
let 
  # The durdraw flake still wraps neofetch, which was removed from nixpkgs.
  # Re-wrap it with hyfetch's maintained fork (neowofetch) plus a `neofetch`
  # shim so durfetch keeps working.
  neofetchShim = pkgs.writeShellScriptBin "neofetch" ''
    exec ${pkgs.hyfetch}/bin/neowofetch "$@"
  '';
  durdrawPkg = inputs.durdraw.packages.${pkgs.stdenv.hostPlatform.system}.durdraw.overrideAttrs (old: {
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath [ pkgs.ansilove pkgs.hyfetch neofetchShim ]}"
    ];
  });
in 
{
  programs.durdraw = {
    enable = true;
    package = durdrawPkg;
    settings = {
      Main = {
        color-mode = 256;           # Color mode (16, 256, or truecolor)
        cursor-mode = "underscore"; # Cursor style
        scroll-colors = true;       # Enable color scrolling
        auto-save = true;           # Auto-save files
      };
      Theme = {
        theme-16 = "~/.durdraw/themes/custom-16.dtheme.ini";
        theme-256 = "~/.durdraw/themes/custom-256.dtheme.ini";
      };
      Keys = {
        # Custom key bindings
        quit = "q";
        save = "s";
      };
    };
  };
}
