{ config, pkgs, ...}:
let 
in 
{
  services.flatpak.update.auto.enable = true;

  # Desktop apps come from Flathub wherever one exists. Anything that needs
  # tight system integration (Steam, kitty, VSCodium, via, ...) stays native.
  services.flatpak.packages = [
    # Browser
    "app.zen_browser.zen"
    # Communication
    "org.signal.Signal"
    # Media
    "com.spotify.Client"
    "org.videolan.VLC"
    "org.fooyin.fooyin"
    "org.qbittorrent.qBittorrent"
    # Productivity
    "org.libreoffice.LibreOffice"
    "com.calibre_ebook.calibre"
    "net.filebot.FileBot"
    # Utilities
    "it.mijorus.gearlever"
    "com.protonvpn.www"
    "io.github.input_leap.input-leap"
  ];

  services.flatpak.overrides = {
    global = {
      Context.filesystems = [
        "xdg-config/gtk-4.0"
        "xdg-config/gtk-3.0"
        "${config.home.homeDirectory}/.themes"
        "${config.home.homeDirectory}/.icons"
        # Game drive, and the backup drive that the home folders link into
        # (flatpak does not follow symlinks out of the sandbox otherwise).
        "/mnt/GD1"
        "/mnt/GD2"
      ];
      Environment = {
        XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
        GTK_THEME = "Dracula";
        ICON_THEME = "Tela-circle-dracula";
      };
    };
  };
}
