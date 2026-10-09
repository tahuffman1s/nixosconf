{ config, pkgs, lib, user, ...}:
let 
  # On/off switches for services, managed by NixOS Updater (Services tab).
  # services.json holds { "<name>": { "enabled": bool, "description": "..." } };
  # the matching NixOS configuration for each name lives here.
  toggles = builtins.fromJSON (builtins.readFile ./services.json);
  enabled = name: (toggles.${name}.enabled or false);

  definitions = {
    openssh = {
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };
    };
    kdeconnect = {
      programs.kdeconnect.enable = true;
    };
    tailscale = {
      services.tailscale.enable = true;
    };
    syncthing = {
      services.syncthing = {
        enable = true;
        user = user.name;
        dataDir = "/home/${user.name}";
        openDefaultPorts = true;
      };
    };
    docker = {
      virtualisation.docker.enable = true;
      users.users.${user.name}.extraGroups = [ "docker" ];
    };
    libvirt = {
      virtualisation.libvirtd.enable = true;
      programs.virt-manager.enable = true;
      users.users.${user.name}.extraGroups = [ "libvirtd" ];
    };
    sunshine = {
      services.sunshine = {
        enable = true;
        autoStart = true;
        capSysAdmin = true;
        openFirewall = true;
      };
    };
    jellyfin = {
      services.jellyfin = {
        enable = true;
        openFirewall = true;
      };
    };
    fwupd = {
      services.fwupd.enable = true;
    };
    ollama = {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-rocm;
      };
    };
  };
in 
{
  config = lib.mkMerge (lib.mapAttrsToList (name: def: lib.mkIf (enabled name) def) definitions);
}
