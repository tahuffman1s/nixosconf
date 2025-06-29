{ config, pkgs, ... }:

let 
  gtkTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Dracula.tar.xz";
    sha256 = "1xrbv4nw918xjm79qpwlbyviis7s86d4pn4j68ll0iqjic0fzkxa";
  };
  iconTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Tela-circle-dracula.tar.xz";
    sha256 = "1kqzw8ajm2hvn1fa0xbx977amq0jblkd2ipsxw7qrb9i0cxm6j6c";
  };
  kdeTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Draculakde.tar.xz";
    sha256 = "16jb6z2x0wmdnlk7lxpa57a36vw8571idfcn3gv9zdps0y68583x";
  };
in 
{
  home.username = "travis";
  home.homeDirectory = "/home/travis";
  home.enableNixpkgsReleaseCheck = false;

  home.packages = with pkgs; [
    fastfetch
    signal-desktop
    mangohud
    gamemode
    gamescope
    qbittorrent
    fooyin
    handbrake
    freetube
    makemkv
    vlc
    jellyfin-media-player
    dracula-theme
    nerd-fonts.fira-mono
    kdePackages.breeze-gtk
  ];

  home.file = {
    ".themes" = {source = "${gtkTheme}";};
    ".icons" = {source = "${iconTheme}";};
    ".local/share/icons" = {source = "${iconTheme}";};
    ".local/share/themes/Dracula" = {source ="${kdeTheme}";};
  };

  gtk = {
    enable = true;
    theme = {
      name = "Dracula";
    };
    iconTheme = {
      name = "Tela-circle-dark";
    };
  };

  programs.git = {
    enable = true;
    userName = "Travis Huffman";
    userEmail = "huffmantravis57@protonmail.com";
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      scan_timeout = 10;
      format = "[┌─|$os > $directory$git_branch$fill|$cmd_duration$time|](bold green)\n[└─>](bold green) ";
      os = {
        format = "[$symbol](bold white)";
        disabled = false;
        symbols = {
          NixOS = "";
        };
      };
      fill = {
        symbol = "─";
        style = "bold green";
      };
      time = {
        disabled = false;
        use_12hr = true;
        format = "[$time]($style) [](bold green)";
      };
      cmd_duration = {
        min_time = 0;
        show_milliseconds = false;
        format = "[took](bold purple) [$duration]($style) at ";
      };
    };
  };

  programs.kitty = {
    enable = true;
    themeFile = "Dracula";
    settings = {
      confirm_os_window_close = 0; 
      font_size = 12;
      font_family = "FiraMono Nerd Font Mono";
      background_opacity = 0.7;
    };
  };

  programs.zoxide = {
    enable = true;
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      alias fetch=fastfetch
      alias update="rm ~/.gtkrc-2.0; sudo nixos-rebuild switch"
      alias cd=z
      alias flake="code /etc/nixos/flake.nix"
      alias conf="code /etc/nixos/configuration.nix"
      alias home="code /etc/nixos/home.nix"
      alias genConf="sudo nixos-generate-config"
      alias ship="code ~/.config/starship.toml"
      alias genHardware="sudo nixos-generate-config"
      alias wipeass="journalctl -xe --unit home-manager-travis"
    '';
  };
  
  services.flatpak.update.auto.enable = true;
  services.flatpak.packages = [
    "io.github.input_leap.input-leap"
    "com.protonvpn.www"
    "org.gtk.Gtk3theme.Breeze"
    "com.calibre_ebook.calibre"
    "net.filebot.FileBot"
    "com.jeffser.Alpaca"
    "com.jeffser.Alpaca.Plugins.Ollama" 
    "com.jeffser.Alpaca.Plugins.AMD"
    rec {
      appId = "org.tahuffman1s.rsensor";
      sha256 = "DCz/EYAHIyEenRtwOB7b+yXylduX+wRaR/58vZ4JKzI=";
      bundle = "${pkgs.fetchurl {
        url = "https://github.com/tahuffman1s/rsensor/releases/download/0.1.0/rsensor.flatpak";
        sha256 = sha256;
      }}";
    }
  ];

  services.flatpak.overrides = {
    global = {
      Context.filesystems = [
        "xdg-config/gtk-4.0"
        "xdg-config/gtk-3.0"
        "/home/travis/.themes"
        "/home/travis/.icons"
      ];
      Environment = {
        XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
        GTK_THEME = "Dracula";
        ICON_THEME = "Tela-circle-dracula";
      };
    };
  };

  programs.vscode = {
    enable = true;
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

  programs.plasma = {
    enable = true;
    workspace = {
      colorScheme = "Dracula";
      theme = "Dracula";
      windowDecorations.library = "org.kde.kwin.aurorae";
      windowDecorations.theme = "__aurorae__svg__Dracula";
      wallpaper = "${pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/tahuffman1s/Wallpapers/refs/heads/main/nix.jpg";
        sha256 = "I7Daq4rI7f09V6uctWr0yIzspDI/K4PBObsm3Vp2fqc=";
      }}";
      iconTheme = "Tela-circle-dracula";
    };
    hotkeys.commands."launch-kitty" = {
      name = "Launch Kitty";
      key = "Ctrl+Alt+T";
      command = "kitty";
    };
    panels = [
      {
        location = "bottom";
        floating = true;
        screen = 0;
        widgets = [
          {
            kickoff = {
              sortAlphabetically = true;
              icon = "nix-snowflake-white";
            };
          }
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.panelspacer"
          {
            iconTasks = {
              launchers = [
                "applications:org.kde.dolphin.desktop"
                "applications:zen.desktop"
                "applications:code.desktop"
                "applications:steam.desktop"
                "applications:signal.desktop"
              ];
            };
          }
          "org.kde.plasma.panelspacer"
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          {
            digitalClock = {
              calendar.firstDayOfWeek = "sunday";
              time.format = "12h";
            };
          }
        ];
      }
    ];
  };
  
  home.stateVersion = "25.05";
}
