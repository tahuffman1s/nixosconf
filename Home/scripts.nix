{ config, pkgs, lib, ...}:
let 
  # Scripts and their companion files from NixOS Updater (Scripts page).
  # Everything in Home/scripts/ listed in scripts.json is installed under
  # ~/.local/share/nixos-scripts/; entries marked "script" also get a link in
  # ~/.local/bin so they are on PATH. Both links resolve into the same
  # directory, so a script finds its companion files next to itself
  # (Python's sys.path[0] and `dirname "$(readlink -f "$0")"` both see them).
  #
  # Scripts marked "postUpdate" are run, in name order, by the generated
  # ~/.local/share/nixos-scripts/post-update after every update (the app's
  # Update action and the unattended updater both call it). A failing script
  # is reported but does not stop the others.
  entries = builtins.fromJSON (builtins.readFile ./scripts.json);
  file = e: ./scripts + "/${e.file}";
  postUpdate = builtins.filter (e: e.script && (e.postUpdate or false)) entries;
  runner = pkgs.writeShellScript "nixos-post-update" ''
    status=0
    ${lib.concatMapStringsSep "\n" (e: ''
      echo "==> ${e.file}"
      "$HOME/.local/bin/${e.file}" || { echo "==> ${e.file} failed with exit code $?"; status=1; }
    '') postUpdate}
    ${lib.optionalString (postUpdate == [ ]) ''echo "No post-update scripts configured."''}
    exit $status
  '';
in 
{
  home.file = lib.listToAttrs (lib.concatMap (e:
    [ { name = ".local/share/nixos-scripts/${e.file}"; value.source = file e; } ]
    ++ lib.optional e.script { name = ".local/bin/${e.file}"; value.source = file e; }
  ) entries) // {
    ".local/share/nixos-scripts/post-update".source = runner;
  };
  home.sessionPath = [ "$HOME/.local/bin" ];
}
