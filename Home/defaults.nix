{ config, pkgs, lib, ...}:
let 
  # Default applications, managed by NixOS Updater (Default Apps page).
  # defaults.json maps a category to a .desktop file name; each category
  # covers the MIME types below. The terminal also goes into kdeglobals,
  # which is where Plasma looks for it.
  defaults = builtins.fromJSON (builtins.readFile ./defaults.json);
  categories = {
    browser = [ "text/html" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" "x-scheme-handler/about" "x-scheme-handler/unknown" ];
    email = [ "x-scheme-handler/mailto" "message/rfc822" ];
    files = [ "inode/directory" ];
    text = [ "text/plain" "text/markdown" "text/x-shellscript" "application/json" "application/x-yaml" "text/x-python" ];
    images = [ "image/png" "image/jpeg" "image/gif" "image/webp" "image/bmp" "image/svg+xml" "image/tiff" "image/avif" ];
    video = [ "video/mp4" "video/x-matroska" "video/webm" "video/x-msvideo" "video/quicktime" "video/mpeg" "video/x-flv" "video/ogg" ];
    music = [ "audio/mpeg" "audio/flac" "audio/x-wav" "audio/ogg" "audio/x-vorbis+ogg" "audio/mp4" "audio/aac" "audio/x-opus+ogg" ];
    pdf = [ "application/pdf" ];
    archives = [ "application/zip" "application/x-tar" "application/gzip" "application/x-7z-compressed" "application/vnd.rar" "application/x-xz" "application/x-bzip2" "application/x-compressed-tar" ];
    torrent = [ "application/x-bittorrent" "x-scheme-handler/magnet" ];
  };
  chosen = lib.filterAttrs (cat: _: (defaults.${cat} or "") != "") categories;
  mimeDefaults = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList (cat: mimes:
    map (m: { name = m; value = defaults.${cat}; }) mimes
  ) chosen));
in 
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = mimeDefaults;
  };

  programs.plasma.configFile.kdeglobals.General = lib.mkIf ((defaults.terminal or "") != "") {
    TerminalService = defaults.terminal;
    TerminalApplication = defaults.terminalExec or (lib.removeSuffix ".desktop" defaults.terminal);
  };
}
