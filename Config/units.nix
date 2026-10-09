{ config, pkgs, lib, ...}:
let 
  # systemd units dropped into NixOS Updater (Services tab). The unit files
  # themselves live in Config/units/; units.json lists them:
  #   { "file": "backup.service", "scope": "system"|"user",
  #     "enabled": true, "wantedBy": ["multi-user.target"] }
  # System units are installed here; user units in Home/units.nix.
  units = builtins.fromJSON (builtins.readFile ./units.json);
  systemUnits = builtins.filter (u: u.scope == "system") units;
in 
{
  systemd.units = lib.listToAttrs (map (u: {
    name = u.file;
    value = {
      text = builtins.readFile (./units + "/${u.file}");
      wantedBy = if u.enabled then u.wantedBy else [ ];
    };
  }) systemUnits);
}
