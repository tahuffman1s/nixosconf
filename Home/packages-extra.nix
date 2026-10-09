{ config, pkgs, lib, ...}:
let 
  # Extra nixpkgs packages added from NixOS Updater (Apps page). packages.json
  # is a list of attribute paths such as "obsidian" or "kdePackages.kate".
  names = builtins.fromJSON (builtins.readFile ./packages.json);
  byPath = name: lib.attrByPath (lib.splitString "." name)
    (throw "Home/packages.json: there is no package '${name}' in nixpkgs") pkgs;
in 
{
  home.packages = map byPath names;
}
