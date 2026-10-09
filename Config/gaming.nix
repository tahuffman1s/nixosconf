{ config, pkgs, ...}:
let 
in 
{
  # Tuned on a Ryzen 7 7700X, Radeon RX 7800 XT, 32 GB DDR5; applies to
  # every machine, with hardware.json choosing the GPU driver.

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

  # GPU driver bits (amdgpu/LACT, NVIDIA, Intel) live in
  # Config/hardware-profile.nix, driven by hardware.json.

  # Wine's NT synchronization primitives: Proton and Wine 10+ use
  # /dev/ntsync for much faster thread sync in Windows games. The kernel
  # ships it as a module that nothing autoloads, so load it at boot and
  # let users open the device.
  boot.kernelModules = [ "ntsync" ];
  services.udev.extraRules = ''
    KERNEL=="ntsync", MODE="0644"
  '';

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
