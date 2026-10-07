{ config, pkgs, ...}:
let 
in 
{
  services.flatpak.update.auto.enable = true;

  # Desktop apps come from Flathub wherever one exists. Anything that needs
  # tight system integration (Steam, kitty, VSCodium, via, spotify-qt, ...)
  # stays a native package.
  services.flatpak.packages = [
    # Browser
    "app.zen_browser.zen"
    # Communication
    "org.signal.Signal"
    # Media
    "org.videolan.VLC"
    "org.fooyin.fooyin"
    "io.freetubeapp.FreeTube"
    "com.github.iwalton3.jellyfin-media-player"
    "fr.handbrake.ghb"
    "com.makemkv.MakeMKV"
    "org.nicotine_plus.Nicotine"
    "org.qbittorrent.qBittorrent"
    # Productivity
    "org.libreoffice.LibreOffice"
    "md.obsidian.Obsidian"
    "com.calibre_ebook.calibre"
    "net.filebot.FileBot"
    # Utilities
    "menu.kando.Kando"
    "it.mijorus.gearlever"
    "com.protonvpn.www"
    "io.github.input_leap.input-leap"
    # Gaming / emulation
    "com.steamgriddb.steam-rom-manager"
    "info.cemu.Cemu"
    "org.DolphinEmu.dolphin-emu"
    "org.duckstation.DuckStation"
    "net.rpcs3.RPCS3"
    "org.ppsspp.PPSSPP"
    "net.pcsx2.PCSX2"
    "io.mgba.mGBA"
    "net.kuribo64.melonDS"
    "io.github.ryubing.Ryujinx"
  ];

  services.flatpak.overrides = {
    global = {
      Context.filesystems = [
        "xdg-config/gtk-4.0"
        "xdg-config/gtk-3.0"
        "/home/travis/.themes"
        "/home/travis/.icons"
        # Game drives, so the emulators can see ROMs and the Steam library.
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
