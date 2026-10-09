{ config, pkgs, ...}:
let 
  # The Flatpak list and permission overrides live in flatpaks.json so the
  # NixOS Updater app can regenerate them from what is actually installed
  # (`nixos-updater scan`). Edit the JSON by hand if you like; the app keeps
  # it sorted. Filesystem entries may use "~/" for the home directory.
  data = builtins.fromJSON (builtins.readFile ./flatpaks.json);
in 
{
  services.flatpak.update.auto.enable = true;
  services.flatpak.packages = data.packages;
  services.flatpak.overrides = data.overrides;
}
