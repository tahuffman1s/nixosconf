{ config, pkgs, ...}:
let 
in 
{
  services.flatpak.update.auto.enable = true;
  services.flatpak.packages = [
    "io.github.input_leap.input-leap"
    "com.protonvpn.www"
    "com.calibre_ebook.calibre"
    "net.filebot.FileBot"
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
}