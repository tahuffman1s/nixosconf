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
      ./Config/users.nix
      ./Config/networking.nix
      ./Config/environment.nix
      ./Config/nixsettings.nix
      ./Apps/bash.nix
      ./Apps/steam.nix
      ./Apps/zen.nix
    ];
  system.stateVersion = "25.11";
}
