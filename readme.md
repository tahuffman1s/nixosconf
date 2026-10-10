# nixosconf

NixOS flake for my desktop: Plasma 6 on nixos-unstable, home-manager, Flatpaks
from Flathub managed with nix-flatpak, Bazaar as the app store, Dracula theme
everywhere.

## Setup

On a NixOS machine, from your own account:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
```

That is the only step after a plain NixOS install. The script builds the
config for the account that ran `sudo`. It opens a small terminal UI (gum,
fetched from nixpkgs) that asks three things, with what it detected already
selected: the graphics card (Radeon, GeForce, Intel, or a hybrid laptop with
an iGPU next to a GeForce), the processor, and whether the machine is a
laptop. A hybrid also asks how to use the NVIDIA GPU (PRIME offload or sync)
and confirms the two PCI bus IDs it found. It also asks whether to mount the
GD1 and GD2 data drives at all, and whether to replace the home folders with
links into `/mnt/GD2/Backup`; both default to yes on a desktop or when a
drive with that label is visible, and to no on a laptop. A laptop gets a
few more: ThinkPad extras (detected), the power profile on the charger and
on battery, a CPU power cap, turbo boost, and whether the firmware's thermal
mode may change the power profile. Enter through the questions keeps the
detected answers. Then it clones
this repo into `~/nixosconf` (owned by you), points `/etc/nixos` at it, writes
`user.nix` with your account name and `hardware.json` with those answers,
generates `hardware-configuration.nix`, finds the GD1 and GD2 drives for
`drives.nix` (by current mount, filesystem label, known UUID, or a picker over
the partitions) and mounts them, runs `nixos-rebuild switch --flake
/etc/nixos`, installs the Flatpaks, and reboots into the new system. Files
that home-manager wants to own are moved aside with an `.hm-backup` suffix
rather than stopping the build. Rerunning it on a machine that already has
the clone asks the hardware questions again (defaulting to the current
`hardware.json`), pulls and switches. Set `NIXOSCONF_NO_REBOOT=1` to skip
the reboot.

Without a terminal, or with `NIXOSCONF_NO_UI=1`, it takes the detected
hardware without asking; `NIXOSCONF_GPU=amd|nvidia|intel|hybrid`,
`NIXOSCONF_CPU=amd|intel`, `NIXOSCONF_LAPTOP=1|0`, and for a hybrid
`NIXOSCONF_IGPU=intel|amd`, `NIXOSCONF_PRIME=offload|sync`,
`NIXOSCONF_IGPU_BUSID` and `NIXOSCONF_NVIDIA_BUSID` override detection.
`NIXOSCONF_DRIVES=1|0` and `NIXOSCONF_HOME_LINKS=1|0` decide the data drives
and the home folder links; `NIXOSCONF_THINKPAD`, `NIXOSCONF_CPU_WATTS`,
`NIXOSCONF_CPU_TURBO`, `NIXOSCONF_FIRMWARE_PROFILE`, `NIXOSCONF_AC_PROFILE`
and `NIXOSCONF_BATTERY_PROFILE` cover the laptop questions.

### Hardware profiles

`hardware.json` drives `Config/hardware-profile.nix`:

| Choice | What it turns on |
| --- | --- |
| GPU `amd` | Mesa, amdgpu in the initrd (early KMS), overdrive for clock and power limits, LACT |
| GPU `nvidia` | The proprietary NVIDIA driver (latest branch) with NVIDIA's open kernel modules, kernel modesetting for Wayland, nvidia-settings, VA-API through nvidia-vaapi-driver, Ozone/Wayland for Chromium apps, nvtop; the kernel drops from `linuxPackages_latest` to the default kernel so the modules build. Needs a Turing (RTX 20 / GTX 16) or newer card. |
| GPU `intel` | Mesa, i915 in the initrd, intel-media-driver and intel-vaapi-driver (VA-API), OpenCL runtime, oneVPL, intel-gpu-tools |
| GPU `hybrid` | An Intel or AMD iGPU (`igpu`) driving the screen plus a GeForce through NVIDIA PRIME, with the same NVIDIA driver setup as above and the iGPU's own drivers. `prime: offload` (default) leaves the NVIDIA GPU powered off until a program uses it: Steam and everything it launches always run on it, anything else with `nvidia-offload <command>`; fine-grained power management turns the card off in between. `prime: sync` makes the NVIDIA GPU render everything, for a laptop that mostly lives on the charger. Both need the PCI bus IDs in `busIds`, which setup.sh reads from `/sys/bus/pci` (`lspci` shows them as `01:00.0`, written `PCI:1:0:0`). |
| CPU `amd` / `intel` | The matching microcode updates |
| `dataDrives` | `false` writes an empty `drives.nix` and disables the mounts; nothing under `/mnt` is touched |
| `homeLinks` | `false` leaves Documents, Downloads, Music, Pictures, Videos, `.ssh` and the book libraries as ordinary folders; `true` needs the GD2 drive |
| `cpuPowerLimitWatts` | A number caps the CPU's sustained package power (Intel RAPL) at boot and after resume, for laptops whose cooler cannot keep up: 30 holds a 45 W i7 in the 80s while gaming and usually smooths the frame rate, because the chip stops thermal-cycling. Turns thermald off, since it would raise the limit again. `null` (default) leaves the firmware's limit |
| `cpuTurbo` | `false` holds the CPU at its base clock (no boost); a coarser version of the power cap |
| `acPowerProfile`, `batteryPowerProfile` | The power profile Plasma applies on the charger (default performance) and on battery (default balanced); low battery is always power saving. On battery the firmware also cuts the GPU's power budget, which no profile can undo |
| `thinkpad` | `true` runs thinkfan with a fan curve that spins up earlier than Lenovo's own and hits full speed before the CPU throttles, enables the fingerprint reader (enrol with `fprintd-enroll`) and TrackPoint middle-button scrolling |
| `firmwarePowerProfile` | Laptops only. `false` stops power-profiles-daemon from following the firmware's own thermal profile, for laptops whose firmware keeps resetting it to balanced; the CPU preference still follows the chosen profile |
| Laptop | power-profiles-daemon (Plasma's battery widget), thermald on Intel, Wi-Fi power saving, lid closes to suspend, power key suspends (long press powers off), rotation sensors, brightnessctl and powertop, zram swappiness back to 60, NVIDIA runtime power management when the GPU is NVIDIA |

To change it later, edit `hardware.json` and run Apply in the updater, or
rerun the setup one-liner.

`hardware.json`, `user.nix`, `hardware-configuration.nix` and `drives.nix`
describe one machine. They are tracked in git (a flake only sees tracked
files) but each machine keeps its own values as uncommitted changes: the
updater never commits them, Push never sends them, and a setup rerun sets
them aside around its pull and restores them. The committed copies are
only the defaults a fresh clone starts from, so a laptop and a desktop can
share everything else in this repo without affecting each other.

To use a branch other than `main`:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo NIXOSCONF_BRANCH=some-branch bash
```

## Day to day

Open **NixOS Updater** from the start menu, or in a terminal:

```sh
nixos-updater update                           # or `update` in fish
nixos-updater scan                             # sync Flatpaks into the config
nixos-updater flush                            # or `flush` in fish
sudo nixos-rebuild switch --flake /etc/nixos   # or `swap` in fish, after editing
```

Update syncs the installed Flatpaks, their permissions and any autostart
entries Plasma created into the config, commits that, refreshes `flake.lock`,
runs `nixos-rebuild switch --flake /etc/nixos` (asking for your password
through polkit), updates the Flatpaks, and offers a reboot if the kernel
changed. Flush removes old generations and boot entries and unused Flatpak
runtimes. Push sends the commits to GitHub.

The app is laid out like System Settings: pages in a sidebar, an activity
log underneath. The Overview page has the big actions; the other pages edit
parts of the config that describe this machine. Each Save commits; Apply (or
Update) rebuilds:

| Page | File | What |
| --- | --- | --- |
| Apps | `Apps/flatpaks.json`, `Home/packages.json` | Search Flathub and the config's pinned nixpkgs, add apps (Flatpaks install right away, nixpkgs packages with the next Apply), remove them; Sync records Bazaar installs and permission changes |
| Autostart | `Home/autostart.json` | Apps and commands started with the Plasma session, with a picker over installed apps |
| Shortcuts | `Home/shortcuts.json` | Global shortcuts that run a command (plasma-manager hotkeys), recorded with a key editor |
| System Units | `Config/units.json`, `Config/units/` | systemd units for the whole machine: drop `.service`/`.timer` files, or create a timer from a name, command and schedule |
| User Units | same | The same for home-manager units that run as you inside your session |
| Scripts | `Home/scripts.json`, `Home/scripts/` | Bash or Python scripts plus companion files; installed side by side in `~/.local/share/nixos-scripts/` (root scripts and their companions in `/etc/nixos-scripts/`) and run from there, so `$(dirname "$0")` finds a companion file next to the script; `~/.local/bin` wrappers put scripts on PATH; Run and Edit buttons; the timer wizard can pick one; scripts ticked "After update" run at the end of every Update or Apply, attended or not; "As root" runs a script with root rights, from the copy the system build installs under `/etc/nixos-scripts/` |
| udev Rules | `Config/udev/` | Drop `*.rules` files; installed as a udev rules package under `/etc/udev/rules.d` on the next Apply |
| Dotfiles | `Home/dotfiles/` | Config files for your apps; the folder mirrors your home (`Home/dotfiles/.config/kitty/kitty.conf` becomes `~/.config/kitty/kitty.conf`) and a dotfile takes over from what a home-manager module would generate for the same app |
| Default Apps | `Home/defaults.json` | Which app opens web links, mail, folders, text, images, video, music, PDFs, archives and torrents, plus the terminal; applied through `xdg.mimeApps` and kdeglobals; can import Plasma's current choices |
| Auto Updates | `Config/autoupdate.json` | A systemd timer that refreshes inputs, rebuilds (for next boot or immediately), updates Flatpaks, and can reboot when the kernel changed |

Terminal equivalents: `nixos-updater unit add|remove|list`,
`nixos-updater script add|remove|run|list`, `nixos-updater defaults list|set|import`,
`nixos-updater app search|add|remove`, `nixos-updater udev add|remove|list` and
`nixos-updater dotfile add|remove|list`.

## Layout

| Path | What |
| --- | --- |
| `flake.nix` | Inputs and the `nixos` system definition |
| `user.nix` | The account the config is built for (written by setup.sh) |
| `drives.nix` | GD1 and GD2 mounts (written by setup.sh) |
| `hardware.json` | GPU (including hybrid iGPU + NVIDIA with PRIME mode and bus IDs), CPU, laptop, data drive and home link choices, read by `Config/hardware-profile.nix`, `drives.nix` and `Home/links.nix` (written by setup.sh) |
| `configuration.nix` | System module list |
| `Config/` | Boot, hardware profile, gaming tuning, networking, locale, services, printing, users, nix settings |
| `Apps/` | Per-app modules (Steam, kitty, fish, VSCodium, Zen, the updater app, ...) |
| `Apps/flatpaks.json` | Installed Flatpaks and their permissions, kept in sync by the updater |
| `Home/packages.json`, `Home/autostart.json`, `Home/shortcuts.json`, `Home/scripts.json` + `Home/scripts/`, `Home/defaults.json`, `Home/dotfiles/`, `Config/units.json` + `Config/units/`, `Config/udev/`, `Config/autoupdate.json` | Edited by the updater's pages |
| `Home/` | home-manager entry point, native packages, home folder links |
| `Theme/` | Plasma and GTK theming |
| `Files/` | Theme archives unpacked at build time |

`Home/links.nix` replaces Documents, Downloads, Music, Pictures, Videos and
`.ssh` with symlinks into `/mnt/GD2/Backup`, and links the book libraries from
`/mnt/GD2/Backup/Books`. It only acts when that drive is mounted, and not at
all when `homeLinks` is false in `hardware.json`.
