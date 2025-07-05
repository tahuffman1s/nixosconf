{ config, pkgs, inputs, ... }:
{
  imports =
    [ 
      ./hardware-configuration.nix
      ./Config/plymouth.nix
      ./Config/boot.nix
      ./Config/hardware.nix
      ./Config/locale.nix
      ./Config/services.nix
      ./Config/users.nix
      ./Config/networking.nix
      ./Config/environment.nix
      ./Config/nixsettings.nix
      ./Apps/bash.nix
      ./Apps/steam.nix
    ];
  system.stateVersion = "25.11";
}
