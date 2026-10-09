{ config, pkgs, lib, ...}:
let 
  # Dotfiles from NixOS Updater (Dotfiles page). Home/dotfiles/ mirrors your
  # home directory: Home/dotfiles/.config/kitty/kitty.conf is installed as
  # ~/.config/kitty/kitty.conf, and so on for every file in there. A dotfile
  # wins over a config file a home-manager module would generate for the same
  # path (kitty, starship, ...), so dropping one in takes over that app.
  #
  # Entries are defined on home.file with the absolute target as the name,
  # which is the form the xdg.configFile mapping and modules like starship
  # use, so the mkForce priority applies against them.
  root = ./dotfiles;
  files = builtins.filter (f: baseNameOf (toString f) != ".gitkeep") (lib.filesystem.listFilesRecursive root);
  relative = f: lib.removePrefix (toString root + "/") (toString f);
  target = f:
    let r = relative f; in
    if lib.hasPrefix ".config/" r
    then "${config.xdg.configHome}/${lib.removePrefix ".config/" r}"
    else "${config.home.homeDirectory}/${r}";
in 
{
  home.file = lib.listToAttrs (map (f: { name = target f; value.source = lib.mkForce f; }) files);
}
