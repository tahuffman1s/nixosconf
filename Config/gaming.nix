{ config, pkgs, ...}:
let 
in 
{
  # Ryzen 7 7700X, Radeon RX 7800 XT, 32 GB DDR5.

  # There was no swap at all before. zram gives games and shader compilation
  # somewhere to spill instead of getting OOM-killed, and costs nothing idle.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # sched_ext with LAVD, the scheduler written for the Steam Deck. It keeps
  # the game's render thread ahead of background work. If it ever dies the
  # kernel falls back to its default scheduler.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
  };

  # Radeon: load amdgpu in the initrd (early KMS), allow clock and power
  # limit changes, and install LACT to manage fan curves and limits.
  hardware.amdgpu = {
    initrd.enable = true;
    overdrive.enable = true;
  };
  services.lact.enable = true;

  # Full kernel preemption: lower latency for a little throughput.
  boot.kernelParams = [ "preempt=full" ];

  # zram is much faster than disk swap, so let the kernel use it readily.
  boot.kernel.sysctl."vm.swappiness" = 180;

  # Mesa's default 1 GB shader cache is too small for big titles; without this
  # they recompile shaders on later launches.
  environment.sessionVariables.MESA_SHADER_CACHE_MAX_SIZE = "10G";

  programs.steam = {
    # Proton-GE alongside Valve's Proton; pick it per game in Steam.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    # Deck-style Big Picture session, selectable at the login screen.
    gamescopeSession.enable = true;
    # Makes Steam Input's mouse/keyboard emulation work under Wayland.
    extest.enable = true;
    # winetricks for Proton prefixes.
    protontricks.enable = true;
    # Firewall ports for Remote Play, LAN game transfers and a dedicated
    # server, instead of hand-maintained port lists in networking.nix.
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
}
