{ config, pkgs, ...}:
let 
in 
{
  # home-manager now has a dedicated VSCodium module that writes to
  # ~/.config/VSCodium instead of VS Code's paths.
  programs.vscodium = {
    enable = true;
    profiles.default = {
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

        # Nix: nixd language server through the nix-ide extension, nixfmt
        # for formatting, and option completion for this flake's NixOS and
        # home-manager options.
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        "nix.serverSettings".nixd = {
          formatting.command = [ "${pkgs.nixfmt}/bin/nixfmt" ];
          options = {
            nixos.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos.options";
            home-manager.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos.options.home-manager.users.type.getSubOptions []";
          };
        };
        "[nix]" = {
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
          "editor.tabSize" = 2;
        };
      };
    };
  };

  # Same tools on the command line.
  home.packages = with pkgs; [
    nixd
    nixfmt
  ];
}
