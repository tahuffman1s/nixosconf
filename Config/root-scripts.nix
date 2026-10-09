{ config, pkgs, lib, ...}:
let 
  # Scripts flagged "root" on the updater's Scripts page. They are installed
  # into /etc/nixos-scripts/ by the system build (so what root runs is exactly
  # what the last rebuild put in the Nix store), and the updater's privileged
  # helper runs them only from there. post-update-root runs the ones also
  # flagged "After update"; the unattended updater calls it as root.
  entries = builtins.fromJSON (builtins.readFile ../Home/scripts.json);
  rootScripts = builtins.filter (e: e.script && (e.root or false)) entries;
  interpreter = e: { python = "${pkgs.python3}/bin/python3 "; bash = "${pkgs.bash}/bin/bash "; }.${e.kind or ""} or "";
  runner = pkgs.writeShellScript "nixos-post-update-root" ''
    status=0
    ${lib.concatMapStringsSep "\n" (e: ''
      echo "==> ${e.file} (as root)"
      ${interpreter e}/etc/nixos-scripts/${e.file} || { echo "==> ${e.file} failed with exit code $?"; status=1; }
    '') (builtins.filter (e: e.postUpdate or false) rootScripts)}
    exit $status
  '';
in 
{
  environment.etc = lib.listToAttrs (map (e: {
    name = "nixos-scripts/${e.file}";
    value.source = ../Home/scripts + "/${e.file}";
  }) rootScripts) // lib.optionalAttrs (rootScripts != [ ]) {
    "nixos-scripts/post-update-root".source = runner;
  };
}
