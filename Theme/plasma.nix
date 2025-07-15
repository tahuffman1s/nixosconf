{ config, pkgs, ...}:
let 
  kdeTheme = builtins.fetchTarball {
    url = "https://github.com/tahuffman1s/nixosconf/raw/refs/heads/main/Files/Draculakde.tar.xz";
    sha256 = "16jb6z2x0wmdnlk7lxpa57a36vw8571idfcn3gv9zdps0y68583x";
  };
in 
{
  home.file = {
    ".local/share/themes/Dracula" = {source ="${kdeTheme}";};
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
                "applications:codium.desktop"
                "applications:steam.desktop"
                "applications:signal.desktop"
                "applications:spotify-qt"
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
}