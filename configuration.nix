{ config, pkgs, inputs, ... }:
{
  imports =
    [ 
      ./hardware-configuration.nix
      ./drives.nix
      ./Config/plymouth.nix
      ./Config/boot.nix
      ./Config/hardware.nix
      ./Config/gaming.nix
      ./Config/locale.nix
      ./Config/services.nix
      ./Config/printing.nix
      ./Config/users.nix
      ./Config/networking.nix
      ./Config/environment.nix
      ./Config/nixsettings.nix
      ./Config/services-toggles.nix
      ./Apps/bash.nix
      ./Apps/steam.nix
      ./Apps/zen.nix
      ./Apps/updater.nix
    ];
  system.stateVersion = "25.11";
}
