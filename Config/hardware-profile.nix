{ config, lib, pkgs, ... }:
let
  # Written by setup.sh after detecting the machine (or asking):
  #   gpu:    "amd" | "nvidia" | "intel"
  #   cpu:    "amd" | "intel"
  #   laptop: true | false
  hw = { cpu = "amd"; gpu = "amd"; laptop = false; }
    // builtins.fromJSON (builtins.readFile ../hardware.json);
  isAmdGpu = hw.gpu == "amd";
  isNvidia = hw.gpu == "nvidia";
  isIntelGpu = hw.gpu == "intel";
in
{
  assertions = [
    { assertion = builtins.elem hw.gpu [ "amd" "nvidia" "intel" ];
      message = "hardware.json: gpu must be amd, nvidia or intel (got ${toString hw.gpu})"; }
    { assertion = builtins.elem hw.cpu [ "amd" "intel" ];
      message = "hardware.json: cpu must be amd or intel (got ${toString hw.cpu})"; }
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
  services.xserver.videoDrivers = lib.mkIf isNvidia [ "nvidia" ];
  hardware.nvidia = lib.mkIf isNvidia {
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    # Suspend/resume support for the driver; needed on laptops, harmless
    # elsewhere but off on desktops to keep wake-ups fast. Fine-grained
    # power management needs PRIME bus IDs, so it is left for a manual
    # hardware.nvidia.prime block if the laptop has a hybrid GPU.
    powerManagement.enable = hw.laptop;
  };
  # The open modules need the driver to build against the kernel, which
  # lags the newest mainline kernel. Use the default LTS-ish kernel for
  # NVIDIA instead of linuxPackages_latest from Config/boot.nix.
  boot.kernelPackages = lib.mkIf isNvidia (lib.mkForce pkgs.linuxPackages);

  # ---------------------------------------------------------------------
  # Intel: media drivers (VA-API for new and old generations), OpenCL and
  # the oneVPL runtime; i915/xe in the initrd for early KMS.
  boot.initrd.kernelModules = lib.mkIf isIntelGpu [ "i915" ];

  hardware.graphics.extraPackages =
    lib.optionals isIntelGpu (with pkgs; [ intel-media-driver intel-vaapi-driver intel-compute-runtime vpl-gpu-rt ])
    ++ lib.optionals isNvidia [ pkgs.nvidia-vaapi-driver ];
  hardware.graphics.extraPackages32 =
    lib.optionals isIntelGpu [ pkgs.driversi686Linux.intel-media-driver pkgs.driversi686Linux.intel-vaapi-driver ];

  environment.sessionVariables = lib.mkMerge [
    (lib.mkIf isIntelGpu { LIBVA_DRIVER_NAME = "iHD"; })
    (lib.mkIf isNvidia {
      LIBVA_DRIVER_NAME = "nvidia";
      # Firefox/Zen video decode through nvidia-vaapi-driver.
      MOZ_DISABLE_RDD_SANDBOX = "1";
      NVD_BACKEND = "direct";
      # Electron/Chromium apps on Wayland with the NVIDIA driver.
      NIXOS_OZONE_WL = "1";
    })
  ];

  # ---------------------------------------------------------------------
  # Laptop: battery-aware power profiles (Plasma's battery widget uses
  # power-profiles-daemon), thermald for Intel, Wi-Fi power saving, lid and
  # power-key handling, rotation sensors.
  services.power-profiles-daemon.enable = hw.laptop;
  services.thermald.enable = hw.laptop && hw.cpu == "intel";
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
  # Touchpads and a laptop keyboard: Plasma's own tools, plus brightness
  # control from the shell for scripts and shortcuts.
  environment.systemPackages = lib.optionals hw.laptop [ pkgs.brightnessctl pkgs.powertop ]
    ++ lib.optionals isNvidia [ pkgs.nvtopPackages.nvidia ]
    ++ lib.optionals isIntelGpu [ pkgs.intel-gpu-tools ];
}
