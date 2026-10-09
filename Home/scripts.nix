{ config, pkgs, lib, ...}:
let 
  # Scripts and their companion files from NixOS Updater (Scripts page).
  # Everything in Home/scripts/ listed in scripts.json is installed under
  # ~/.local/share/nixos-scripts/; entries marked "script" also get a link in
  # ~/.local/bin so they are on PATH. Both links resolve into the same
  # directory, so a script finds its companion files next to itself
  # (Python's sys.path[0] and `dirname "$(readlink -f "$0")"` both see them).
  entries = builtins.fromJSON (builtins.readFile ./scripts.json);
  file = e: ./scripts + "/${e.file}";
in 
{
  home.file = lib.listToAttrs (lib.concatMap (e:
    [ { name = ".local/share/nixos-scripts/${e.file}"; value.source = file e; } ]
    ++ lib.optional e.script { name = ".local/bin/${e.file}"; value.source = file e; }
  ) entries);
  home.sessionPath = [ "$HOME/.local/bin" ];
}
