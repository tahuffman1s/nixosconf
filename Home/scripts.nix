{ config, pkgs, lib, ...}:
let 
  # Scripts and their companion files from NixOS Updater (Scripts page).
  # Everything in Home/scripts/ listed in scripts.json is installed side by
  # side in ~/.local/share/nixos-scripts/, and scripts are run from there, so
  # `$(dirname "$0")` or Python's __file__ finds the companion files next to
  # the script. ~/.local/bin/<script> is a small wrapper that runs that copy,
  # which puts the scripts on PATH.
  #
  # Scripts marked "postUpdate" (and not "root") are run, in name order, by
  # the generated post-update runner after every update; the app runs them
  # itself and the unattended updater uses the runner. Scripts marked "root"
  # are handled by Config/root-scripts.nix.
  entries = builtins.fromJSON (builtins.readFile ./scripts.json);
  dir = "${config.home.homeDirectory}/.local/share/nixos-scripts";
  # Call the interpreter explicitly: a "#!/bin/bash" shebang does not resolve on NixOS.
  interpreter = e: { python = "${pkgs.python3}/bin/python3 "; bash = "${pkgs.bash}/bin/bash "; }.${e.kind or ""} or "";
  wrapper = e: ''
    #!${pkgs.runtimeShell}
    exec ${interpreter e}"${dir}/${e.file}" "$@"
  '';
  postUpdate = builtins.filter (e: e.script && (e.postUpdate or false) && !(e.root or false)) entries;
  runner = pkgs.writeShellScript "nixos-post-update" ''
    status=0
    ${lib.concatMapStringsSep "\n" (e: ''
      echo "==> ${e.file}"
      ${interpreter e}"${dir}/${e.file}" || { echo "==> ${e.file} failed with exit code $?"; status=1; }
    '') postUpdate}
    ${lib.optionalString (postUpdate == [ ]) ''echo "Nothing to run."''}
    exit $status
  '';
in 
{
  home.file = lib.listToAttrs (lib.concatMap (e:
    [ { name = ".local/share/nixos-scripts/${e.file}"; value.source = ./scripts + "/${e.file}"; } ]
    ++ lib.optional e.script { name = ".local/bin/${e.file}"; value = { text = wrapper e; executable = true; }; }
  ) entries) // {
    ".local/share/nixos-scripts/post-update".source = runner;
  };
  home.sessionPath = [ "$HOME/.local/bin" ];
}
