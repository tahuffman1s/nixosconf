{ config, lib, pkgs, ... }:
let
  # Written by setup.sh after detecting the machine (or asking):
  #   gpu:    "amd" | "nvidia" | "intel" | "hybrid"
  #   igpu:   "intel" | "amd"            (hybrid: the iGPU that drives the screen)
  #   prime:  "offload" | "sync"         (hybrid: how the NVIDIA GPU is used)
  #   busIds: { igpu = "PCI:0:2:0"; nvidia = "PCI:1:0:0"; }   (hybrid)
  #   cpu:    "amd" | "intel"
  #   laptop: true | false
  #   firmwarePowerProfile: true | false   laptop: let the firmware's thermal
  #           profile (ACPI platform_profile) drive the power profile. Some
  #           laptops reset it to balanced on their own; false tells
  #           power-profiles-daemon to ignore it and only drive the CPU.
  #   cpuPowerLimitWatts: null | number   cap the CPU's sustained package
  #           power (Intel RAPL PL1). For laptops whose cooler cannot keep up:
  #           30 holds a 45 W i7 in the 80s while gaming. Replaces thermald.
  #   cpuTurbo: true | false   false keeps the CPU at its base clock (no boost)
  #   thinkpad: true | false   ThinkPad extras: thinkfan with a curve that
  #           spins up earlier than Lenovo's, fingerprint reader, TrackPoint
  #   dataDrives: true | false   mount GD1/GD2 (drives.nix)
  #   homeLinks:  true | false   link the home folders into /mnt/GD2/Backup (Home/links.nix)
  hw = {
    cpu = "amd"; gpu = "amd"; igpu = "intel"; prime = "offload";
    busIds = { igpu = ""; nvidia = ""; }; laptop = false;
    dataDrives = true; homeLinks = true; firmwarePowerProfile = true;
    cpuPowerLimitWatts = null; cpuTurbo = true; thinkpad = false;
  } // builtins.fromJSON (builtins.readFile ../hardware.json);
  powerCap = hw.cpuPowerLimitWatts;
  tuneCpu = powerCap != null || !hw.cpuTurbo;
  isAmdGpu = hw.gpu == "amd";
  isHybrid = hw.gpu == "hybrid";
  isNvidia = hw.gpu == "nvidia" || isHybrid;
  isIntelGpu = hw.gpu == "intel" || (isHybrid && hw.igpu == "intel");
  offload = isHybrid && hw.prime == "offload";
  sync = isHybrid && hw.prime == "sync";
  # Environment that makes a program render on the NVIDIA GPU under offload.
  offloadEnv = {
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
  };
in
{
  assertions = [
    { assertion = builtins.elem hw.gpu [ "amd" "nvidia" "intel" "hybrid" ];
      message = "hardware.json: gpu must be amd, nvidia, intel or hybrid (got ${toString hw.gpu})"; }
    { assertion = builtins.elem hw.cpu [ "amd" "intel" ];
      message = "hardware.json: cpu must be amd or intel (got ${toString hw.cpu})"; }
    { assertion = isHybrid -> builtins.elem hw.igpu [ "intel" "amd" ];
      message = "hardware.json: igpu must be intel or amd (got ${toString hw.igpu})"; }
    { assertion = isHybrid -> builtins.elem hw.prime [ "offload" "sync" ];
      message = "hardware.json: prime must be offload or sync (got ${toString hw.prime})"; }
    { assertion = powerCap == null || (builtins.isInt powerCap && powerCap >= 5 && powerCap <= 500);
      message = "hardware.json: cpuPowerLimitWatts must be null or a whole number of watts (got ${toString powerCap})"; }
    { assertion = isHybrid -> (hw.busIds.igpu != "" && hw.busIds.nvidia != "");
      message = "hardware.json: a hybrid GPU needs busIds.igpu and busIds.nvidia (PCI:bus:device:function, from lspci). Rerun setup.sh or fill them in."; }
  ];

  # Microcode for whichever CPU is in the box.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkIf (hw.cpu == "amd") true;
  hardware.cpu.intel.updateMicrocode = lib.mkIf (hw.cpu == "intel") true;

  # ---------------------------------------------------------------------
  # Radeon: Mesa from nixos-unstable, amdgpu in the initrd (early KMS),
  # clock and power limit changes allowed, LACT for fan curves and limits.
  hardware.amdgpu = lib.mkIf isAmdGpu {
    initrd.enable = true;
    overdrive.enable = true;
  };
  services.lact.enable = isAmdGpu;

  # ---------------------------------------------------------------------
  # NVIDIA: the proprietary user-space driver with NVIDIA's open kernel
  # modules (Turing and newer). Latest production/new-feature branch, KMS
  # on so Wayland works, nvidia-settings in the menu.
  #
  # Hybrid laptops add PRIME. "offload": the iGPU drives the screen, the
  # NVIDIA GPU sleeps until a program asks for it (`nvidia-offload app`;
  # Steam always does), best on battery. "sync": the NVIDIA GPU renders
  # everything and the iGPU only scans it out, best plugged in.
  services.xserver.videoDrivers = lib.mkIf isNvidia [ "nvidia" ];
  hardware.nvidia = lib.mkIf isNvidia {
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    # Suspend/resume support for the driver; needed on laptops, off on
    # desktops to keep wake-ups fast. Fine-grained power management turns
    # the NVIDIA GPU fully off while idle; it needs PRIME offload.
    powerManagement.enable = hw.laptop;
    powerManagement.finegrained = offload;
    prime = lib.mkIf isHybrid {
      nvidiaBusId = hw.busIds.nvidia;
      intelBusId = lib.mkIf (hw.igpu == "intel") hw.busIds.igpu;
      amdgpuBusId = lib.mkIf (hw.igpu == "amd") hw.busIds.igpu;
      offload.enable = offload;
      offload.enableOffloadCmd = offload;   # the `nvidia-offload` command
      sync.enable = sync;
    };
  };
  # The open modules need the driver to build against the kernel, which
  # lags the newest mainline kernel. Use the default LTS-ish kernel for
  # NVIDIA instead of linuxPackages_latest from Config/boot.nix.
  boot.kernelPackages = lib.mkIf isNvidia (lib.mkForce pkgs.linuxPackages);

  # Under offload, Steam and everything it launches render on the NVIDIA
  # GPU without per-game launch options.
  programs.steam.package = lib.mkIf offload (pkgs.steam.override { extraEnv = offloadEnv; });

  # ---------------------------------------------------------------------
  # Intel: media drivers (VA-API for new and old generations), OpenCL and
  # the oneVPL runtime; i915 in the initrd for early KMS.
  boot.initrd.kernelModules = lib.mkIf isIntelGpu [ "i915" ];

  hardware.graphics.extraPackages =
    lib.optionals isIntelGpu (with pkgs; [ intel-media-driver intel-vaapi-driver intel-compute-runtime vpl-gpu-rt ])
    ++ lib.optionals (hw.gpu == "nvidia") [ pkgs.nvidia-vaapi-driver ];
  hardware.graphics.extraPackages32 =
    lib.optionals isIntelGpu [ pkgs.driversi686Linux.intel-media-driver pkgs.driversi686Linux.intel-vaapi-driver ];

  environment.sessionVariables = lib.mkMerge [
    (lib.mkIf isIntelGpu { LIBVA_DRIVER_NAME = "iHD"; })
    # Video decode through nvidia-vaapi-driver only when NVIDIA drives the
    # screen; on a hybrid the iGPU's decoder is the one that is always on.
    (lib.mkIf (hw.gpu == "nvidia") {
      LIBVA_DRIVER_NAME = "nvidia";
      MOZ_DISABLE_RDD_SANDBOX = "1";
      NVD_BACKEND = "direct";
    })
    # Electron/Chromium apps on Wayland with the NVIDIA driver.
    (lib.mkIf isNvidia { NIXOS_OZONE_WL = "1"; })
  ];

  # ---------------------------------------------------------------------
  # Laptop: battery-aware power profiles (Plasma's battery widget uses
  # power-profiles-daemon), thermald for Intel, Wi-Fi power saving, lid and
  # power-key handling, rotation sensors.
  services.power-profiles-daemon.enable = hw.laptop;
  # The daemon follows every change the firmware makes to its platform
  # profile, so a laptop whose firmware flips back to balanced on AC events
  # or thermals drags the chosen profile with it. Blocking the platform
  # driver leaves the firmware alone and keeps the CPU preference in charge.
  systemd.services.power-profiles-daemon.serviceConfig.ExecStart =
    lib.mkIf (hw.laptop && !hw.firmwarePowerProfile) [
      ""
      "${config.services.power-profiles-daemon.package}/libexec/power-profiles-daemon --block-driver=platform_profile"
    ];
  # thermald raises the power limit back to the maximum whenever the chip is
  # cool, so it is off when a fixed cap is configured.
  services.thermald.enable = hw.laptop && hw.cpu == "intel" && powerCap == null;

  # ---------------------------------------------------------------------
  # CPU power cap and turbo, applied at boot and after resume (firmware
  # restores its own limits on wake). Package-level RAPL zones only, both
  # the MSR and MMIO interfaces, since the higher of the two wins.
  systemd.services.cpu-power-limits = lib.mkIf tuneCpu {
    description = "CPU power limit and turbo settings from hardware.json";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${lib.optionalString (powerCap != null) ''
        for d in /sys/class/powercap/intel-rapl*:[0-9]*; do
          case "$d" in *:*:*) continue ;; esac
          [ -w "$d/constraint_0_power_limit_uw" ] || continue
          echo ${toString (powerCap * 1000000)} > "$d/constraint_0_power_limit_uw"
          # Short bursts (PL2) may go a little higher than the sustained cap.
          [ -w "$d/constraint_1_power_limit_uw" ] &&             echo ${toString ((powerCap + 10) * 1000000)} > "$d/constraint_1_power_limit_uw" || true
          echo "cpu-power-limits: $d sustained ${toString powerCap} W"
        done
      ''}
      ${lib.optionalString (!hw.cpuTurbo) ''
        [ -w /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
        [ -w /sys/devices/system/cpu/cpufreq/boost ] && echo 0 > /sys/devices/system/cpu/cpufreq/boost || true
        echo "cpu-power-limits: turbo off"
      ''}
    '';
  };
  powerManagement.resumeCommands = lib.mkIf tuneCpu ''
    ${pkgs.systemd}/bin/systemctl restart cpu-power-limits.service || true
  '';

  # ---------------------------------------------------------------------
  # ThinkPad: Lenovo's embedded-controller fan curve waits until the CPU is
  # already hot. thinkfan takes over through thinkpad_acpi with a curve that
  # starts earlier and reaches full speed before the throttle point; if it
  # ever stops, the fan goes back to the firmware's automatic control.
  services.thinkfan = lib.mkIf hw.thinkpad {
    enable = true;
    levels = [
      [ 0 0 50 ]
      [ 2 45 58 ]
      [ 4 55 66 ]
      [ 6 63 76 ]
      [ 7 73 84 ]
      [ "level full-speed" 82 32767 ]
    ];
  };
  services.fprintd.enable = lib.mkIf hw.thinkpad true;
  hardware.trackpoint = lib.mkIf hw.thinkpad { enable = true; emulateWheel = true; };
  services.upower.enable = lib.mkIf hw.laptop true;
  hardware.sensor.iio.enable = hw.laptop;
  networking.networkmanager.wifi.powersave = lib.mkIf hw.laptop true;
  services.logind.settings.Login = lib.mkIf hw.laptop {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
  };
  boot.kernelParams = lib.optionals hw.laptop [ "mem_sleep_default=deep" ];
  # The desktop sysctl in gaming.nix pushes everything into zram; on a
  # laptop that keeps the CPU busier than it needs to be.
  boot.kernel.sysctl."vm.swappiness" = lib.mkIf hw.laptop (lib.mkForce 60);
  # Brightness control from the shell for scripts and shortcuts, powertop
  # for finding what drains the battery, GPU monitors for the card in use.
  environment.systemPackages = lib.optionals hw.laptop [ pkgs.brightnessctl pkgs.powertop ]
    ++ lib.optionals isNvidia [ pkgs.nvtopPackages.nvidia ]
    ++ lib.optionals isIntelGpu [ pkgs.intel-gpu-tools ];
}
