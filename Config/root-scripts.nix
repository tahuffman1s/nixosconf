{ config, pkgs, lib, ...}:
let 
  # Scripts flagged "root" on the updater's Scripts page, installed with the
  # companion files next to them under /etc/nixos-scripts/ by the system build
  # (so what root runs is exactly what the last rebuild put in the Nix store).
  # The updater's privileged helper runs only names listed in
  # /etc/nixos-scripts/.root-scripts, from that directory, so `$(dirname "$0")`
  # finds the companion files. post-update-root runs the ones also flagged
  # "After update"; the unattended updater calls it as root.
  entries = builtins.fromJSON (builtins.readFile ../Home/scripts.json);
  rootScripts = builtins.filter (e: e.script && (e.root or false)) entries;
  companions = builtins.filter (e: !e.script) entries;
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
  }) (rootScripts ++ companions)) // lib.optionalAttrs (rootScripts != [ ]) {
    "nixos-scripts/post-update-root".source = runner;
    "nixos-scripts/.root-scripts".text = lib.concatMapStrings (e: "${e.file}\n") rootScripts;
  };
}
