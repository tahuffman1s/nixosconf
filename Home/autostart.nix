{ config, pkgs, lib, ...}:
let 
  # Apps started with the Plasma session. Managed by NixOS Updater
  # (Autostart tab), which also imports entries Plasma's own settings add.
  # Each entry: { "file": "x.desktop", "name": "...", "exec": "...", "icon": "..." }
  entries = builtins.fromJSON (builtins.readFile ./autostart.json);
  desktop = e: ''
    [Desktop Entry]
    Type=Application
    Name=${e.name}
    Exec=${e.exec}
    Icon=${e.icon or ""}
    X-KDE-StartupNotify=false
  '';
in 
{
  xdg.configFile = lib.listToAttrs (map (e: {
    name = "autostart/${e.file}";
    value.text = desktop e;
  }) entries);
}
