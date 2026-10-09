{ config, pkgs, lib, ...}:
let 
  # udev rules dropped into NixOS Updater (udev Rules page). Every *.rules
  # file in Config/udev/ is installed under /etc/udev/rules.d on the next
  # rebuild; udev reloads them as part of activation.
  dir = ./udev;
  files = builtins.filter (n: lib.hasSuffix ".rules" n) (builtins.attrNames (builtins.readDir dir));
  rules = pkgs.runCommand "nixosconf-udev-rules" { } ''
    mkdir -p $out/lib/udev/rules.d
    ${lib.concatMapStringsSep "\n" (f: ''cp ${dir + "/${f}"} "$out/lib/udev/rules.d/${f}"'') files}
  '';
in 
{
  services.udev.packages = lib.optional (files != [ ]) rules;
}
