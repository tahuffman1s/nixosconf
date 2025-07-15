{ config, pkgs, ...}:
let 
in 
{
  services.spotifyd = {
    enable = true;
    settings = 
    {
      global = {
        zeroconf_port = 57621;
        backend = "pulseaudio";
        device_name = "Big Black Computer";
        bitrate = 320;
      };
    };
  };
}