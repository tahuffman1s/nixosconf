{ config, pkgs, lib, user, ...}:
let 
  nixos-updater = pkgs.callPackage ./updater { };
  helper = "${nixos-updater}/libexec/nixos-updater-helper";

  # Unattended updates, managed by NixOS Updater (Auto Updates tab):
  # { enabled, schedule (systemd OnCalendar), mode "boot"|"switch",
  #   reboot (only when the kernel changed), flatpaks }
  auto = builtins.fromJSON (builtins.readFile ../Config/autoupdate.json);
in 
{
  # The updater app: start menu entry, icon, and the polkit action that lets
  # its privileged helper run nixos-rebuild and the garbage collector.
  environment.systemPackages = [ nixos-updater ];

  systemd.services.nixos-updater-auto = lib.mkIf auto.enabled {
    description = "Unattended NixOS update";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ "/run/wrappers" "/run/current-system/sw" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${helper} auto ${user.name} ${auto.mode} ${if auto.reboot then "1" else "0"} ${if auto.flatpaks then "1" else "0"}";
    };
  };
  systemd.timers.nixos-updater-auto = lib.mkIf auto.enabled {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = auto.schedule;
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };
}
