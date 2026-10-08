{ config, pkgs, ...}:
let 
in 
{
  # CUPS with drivers for the Epson ET-2750 EcoTank. Epson's own ESC/P-R
  # driver is the one Epson ships for this model; Gutenprint is there as a
  # second option and for anything else that turns up. The printer also does
  # IPP Everywhere, which CUPS can use driverless once Avahi finds it.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      epson-escpr
      epson-escpr2
      gutenprint
      gutenprintBin
    ];
  };

  # Network printer discovery (mDNS / DNS-SD).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
