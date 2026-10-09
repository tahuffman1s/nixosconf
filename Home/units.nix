{ config, pkgs, lib, ...}:
let 
  # User-scope systemd units from NixOS Updater (Services tab); see
  # Config/units.nix for the format. The unit file is linked into
  # ~/.config/systemd/user and, when enabled, into the .wants directory of
  # each target its [Install] section names, which is what `systemctl
  # --user enable` would do.
  units = builtins.fromJSON (builtins.readFile ../Config/units.json);
  userUnits = builtins.filter (u: u.scope == "user") units;
  unitFiles = lib.listToAttrs (map (u: {
    name = "systemd/user/${u.file}";
    value.source = ../Config/units + "/${u.file}";
  }) userUnits);
  wants = lib.listToAttrs (lib.concatMap (u:
    lib.optionals u.enabled (map (target: {
      name = "systemd/user/${target}.wants/${u.file}";
      value.source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/systemd/user/${u.file}";
    }) u.wantedBy)
  ) userUnits);
in 
{
  xdg.configFile = unitFiles // wants;
  # Start, stop or restart user units whose files changed on activation.
  systemd.user.startServices = "sd-switch";
}
