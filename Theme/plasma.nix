{ config, pkgs, ...}:
let 
  # Shipped in this repo (Files/), unpacked in a derivation instead of being
  # downloaded from GitHub at evaluation time.
  kdeTheme = pkgs.runCommand "dracula-kde-theme" { } ''
    mkdir -p "$out"
    tar --warning=no-unknown-keyword -xJf ${../Files/Draculakde.tar.xz} -C "$out"
  '';
in 
{
  home.file = {
    ".local/share/themes/Dracula" = {source ="${kdeTheme}/Dracula";};
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
                "applications:app.zen_browser.zen.desktop"
                "applications:codium.desktop"
                "applications:steam.desktop"
                "applications:org.signal.Signal.desktop"
                "applications:com.spotify.Client.desktop"
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
