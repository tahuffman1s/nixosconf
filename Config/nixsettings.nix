{ config, pkgs, user, ...}:
let 
in 
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Let scripts written for other distros run as-is: /bin/bash, /usr/bin/env
  # python3 and friends resolve to whatever is on PATH.
  services.envfs.enable = true;
  # Let ordinary (non-Nix) dynamically linked binaries run, e.g. a downloaded
  # service binary started from a dropped-in systemd unit.
  programs.nix-ld.enable = true;

  # /etc/nixos is a symlink to the user's checkout. Root runs nixos-rebuild
  # (and the updater app runs it through polkit), and nix refuses to read a git repo
  # owned by someone else unless it is listed here.
  programs.git = {
    enable = true;
    config.safe.directory = [
      "/etc/nixos"
      "/home/${user.name}/nixosconf"
    ];
  };

  # GitHub's SSH host key, so pushing the config over SSH never stops at a
  # host-key prompt. From https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  programs = {
      appimage = {
        enable = true;
        binfmt = true;
        package = pkgs.appimage-run.override {
          extraPkgs = pkgs: [ pkgs.libxshmfence ];
        };
      };
  };
}