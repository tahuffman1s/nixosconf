{ config, pkgs, ...}:
let 
in 
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      jnoortheen.nix-ide
      vscodevim.vim
      tamasfe.even-better-toml 
      rust-lang.rust-analyzer 
    ];
    userSettings = {
      "workbench.colorTheme" = "Dracula Theme";
      "window.titleBarStyle" = "native";
      "window.menuBarVisibility" = "toggle";
      "window.customTitleBarVisibility" = "never";
      "editor.fontFamily" = "'FiraMono Nerd Font Mono', 'monospace', monospace";    
      "git.openRepositoryInParentFolders" = "always";
    };
  };
}