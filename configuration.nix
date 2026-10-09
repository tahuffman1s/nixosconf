{ config, pkgs, inputs, ... }:
{
  imports =
    [ 
      ./hardware-configuration.nix
      ./drives.nix
      ./Config/plymouth.nix
      ./Config/boot.nix
      ./Config/hardware.nix
      ./Config/hardware-profile.nix
      ./Config/gaming.nix
      ./Config/locale.nix
      ./Config/services.nix
      ./Config/printing.nix
      ./Config/users.nix
      ./Config/networking.nix
      ./Config/environment.nix
      ./Config/nixsettings.nix
      ./Config/units.nix
      ./Config/root-scripts.nix
      ./Config/udev.nix
      ./Apps/bash.nix
      ./Apps/steam.nix
      ./Apps/zen.nix
      ./Apps/updater.nix
    ];
  system.stateVersion = "25.11";
}
