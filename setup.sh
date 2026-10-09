#!/usr/bin/env bash
#
# Set up this machine to use the nixosconf flake. Run it from your normal
# account with sudo:
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
#
# It uses the account that ran sudo, asks a few questions about the hardware
# (GPU, CPU, laptop) with what it detected already selected, clones the repo
# into that account's home, points /etc/nixos at the clone, writes user.nix,
# hardware.json, hardware-configuration.nix and drives.nix for this machine,
# and switches to the new system.
#
# Environment overrides:
#   NIXOSCONF_BRANCH            branch to check out        (default: main)
#   NIXOSCONF_DIR               where to clone             (default: ~/nixosconf)
#   NIXOSCONF_REPO              git URL of the config repo
#   NIXOSCONF_USER              account to set up          (default: the sudo user)
#   NIXOSCONF_GPU               amd | nvidia | intel | hybrid  (default: detected, then asked)
#   NIXOSCONF_IGPU              intel | amd                hybrid: the iGPU
#   NIXOSCONF_PRIME             offload | sync             hybrid: how the NVIDIA GPU is used
#   NIXOSCONF_IGPU_BUSID, NIXOSCONF_NVIDIA_BUSID   hybrid: PCI:bus:device:function
#   NIXOSCONF_CPU               amd | intel                (default: detected, then asked)
#   NIXOSCONF_LAPTOP            1 | 0                      (default: detected, then asked)
#   NIXOSCONF_DRIVES            1 | 0   mount the GD1/GD2 data drives   (default: detected, then asked)
#   NIXOSCONF_HOME_LINKS        1 | 0   link Documents, Downloads, ... and .ssh into /mnt/GD2/Backup
#   NIXOSCONF_NO_UI=1           take the detected/overridden hardware without asking
#   NIXOSCONF_REGEN_HARDWARE=1  rewrite hardware-configuration.nix and drives.nix
#                               on an existing clone (always done on a fresh one)
#   NIXOSCONF_NO_REBOOT=1       do not reboot at the end
#   DRY_RUN=1                   print the state-changing steps instead of running them
#
# After a plain NixOS install this is the only step: it ends by installing the
# Flatpaks and rebooting into the new system.

set -euo pipefail

REPO="${NIXOSCONF_REPO:-https://github.com/tahuffman1s/nixosconf.git}"
BRANCH="${NIXOSCONF_BRANCH:-main}"
LINK="/etc/nixos"
FLAKE_HOST="nixos"          # nixosConfigurations.<name> in flake.nix
DRIVES="GD1 GD2"            # mounted at /mnt/<name>, written to drives.nix
DRY_RUN="${DRY_RUN:-0}"

export NIX_CONFIG="experimental-features = nix-command flakes"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# State-changing steps go through here so DRY_RUN can show them.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '   + %s\n' "$*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Who is this for?

[ -e /etc/NIXOS ] || [ "$DRY_RUN" = 1 ] || die "This only works on NixOS."

if [ "$(id -u)" -ne 0 ]; then
  die "Run this with sudo from your own account:
  curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/${BRANCH}/setup.sh | sudo bash"
fi

USER_NAME="${NIXOSCONF_USER:-${SUDO_USER:-}}"
[ -n "$USER_NAME" ] || USER_NAME="$(logname 2>/dev/null || true)"
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] \
  || die "Could not tell which account to set up. Run with sudo from your own account, or set NIXOSCONF_USER."

passwd_entry="$(getent passwd "$USER_NAME" || true)"
[ -n "$passwd_entry" ] || die "No such user: $USER_NAME"
HOME_DIR="$(printf '%s' "$passwd_entry" | cut -d: -f6)"
FULL_NAME="$(printf '%s' "$passwd_entry" | cut -d: -f5 | cut -d, -f1)"
[ -n "$FULL_NAME" ] || FULL_NAME="$USER_NAME"
HOME_DIR="${NIXOSCONF_HOME_DIR:-$HOME_DIR}"
DIR="${NIXOSCONF_DIR:-$HOME_DIR/nixosconf}"

say "Setting up for user $USER_NAME ($FULL_NAME), config in $DIR"

as_user() { run sudo -u "$USER_NAME" -H env NIX_CONFIG="$NIX_CONFIG" "$@"; }

# Write a file into the checkout, owned by the user.
write_as_user() { # path, content on stdin
  if [ "$DRY_RUN" = 1 ]; then
    printf '   + write %s:\n' "$1"; sed 's/^/     | /'
  else
    install -o "$USER_NAME" -g "$(id -gn "$USER_NAME")" -m 644 /dev/stdin "$1"
  fi
}

# git is not installed on a fresh NixOS; borrow it from nixpkgs if needed.
# Tries the flake registry first, then the nixos channel the installer set up.
find_git() {
  if command -v git >/dev/null 2>&1; then
    command -v git
    return 0
  fi
  local out=""
  out="$(nix build --no-link --print-out-paths "nixpkgs#git^out" 2>/dev/null)" || out=""
  if [ -z "$out" ]; then
    out="$(nix-build --no-out-link '<nixpkgs>' -A git 2>/dev/null)" || out=""
  fi
  if [ -n "$out" ] && [ -x "$out/bin/git" ]; then
    echo "$out/bin/git"
    return 0
  fi
  return 1
}

if command -v git >/dev/null 2>&1; then
  GIT="$(command -v git)"
elif [ "$DRY_RUN" = 1 ]; then
  GIT=git
else
  say "git is not installed, fetching it from nixpkgs"
  GIT="$(find_git)" || die "Could not get git from nixpkgs. Check the network, then rerun."
fi

# ---------------------------------------------------------------------------
# Terminal UI: gum from nixpkgs when there is a terminal to draw on, plain
# prompts otherwise. `curl | sudo bash` has the script on stdin, so every
# prompt talks to /dev/tty directly.

HAVE_TTY=0
{ : </dev/tty >/dev/tty; } 2>/dev/null && HAVE_TTY=1
NO_UI="${NIXOSCONF_NO_UI:-0}"

GUM=""
if [ "$HAVE_TTY" = 1 ] && [ "$NO_UI" != 1 ]; then
  if command -v gum >/dev/null 2>&1; then
    GUM="$(command -v gum)"
  elif [ "$DRY_RUN" != 1 ]; then
    say "Fetching the setup UI (gum) from nixpkgs"
    out="$(nix build --no-link --print-out-paths "nixpkgs#gum^out" 2>/dev/null)" || out=""
    [ -n "$out" ] || out="$(nix-build --no-out-link '<nixpkgs>' -A gum 2>/dev/null)" || out=""
    [ -n "$out" ] && [ -x "$out/bin/gum" ] && GUM="$out/bin/gum"
  fi
fi

# Every gum call draws on the terminal and reads keys from it.
ui() { "$GUM" "$@" </dev/tty >/dev/tty; }

# box "title" line...
box() {
  local title="$1"; shift
  if [ -n "$GUM" ]; then
    "$GUM" style --border rounded --border-foreground 212 --padding "0 2" --margin "1 0" \
      "$("$GUM" style --bold --foreground 212 "$title")" "$@" >/dev/tty
  else
    echo; echo "  $title"; printf '    %s\n' "$@"; echo
  fi
}

# choose "header" "default" item... -> prints the chosen item (first word is the key)
choose() {
  local header="$1" default="$2"; shift 2
  local items=("$@") pick="" i=1 n
  if [ -n "$GUM" ]; then
    pick="$("$GUM" choose --header "$header" --selected "$default" --cursor "> " \
             --header.foreground 212 --cursor.foreground 212 --selected.foreground 212 \
             "${items[@]}" </dev/tty 2>/dev/tty)" || pick=""
  elif [ "$HAVE_TTY" = 1 ] && [ "$NO_UI" != 1 ]; then
    {
      echo; echo "$header"
      for n in "${items[@]}"; do
        if [ "$n" = "$default" ]; then printf '  %d) %s  [default]\n' "$i" "$n"; else printf '  %d) %s\n' "$i" "$n"; fi
        i=$((i + 1))
      done
    } >/dev/tty
    read -r -p "Choice [1-${#items[@]}]: " n </dev/tty || n=""
    [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#items[@]}" ] && pick="${items[$((n - 1))]}"
  fi
  [ -n "$pick" ] || pick="$default"
  printf '%s\n' "$pick"
}

# confirm "question" yes|no -> exit status
confirm() {
  local q="$1" default="$2" a
  if [ -n "$GUM" ]; then
    if [ "$default" = yes ]; then ui confirm --default=true "$q"; else ui confirm --default=false "$q"; fi
    return $?
  elif [ "$HAVE_TTY" = 1 ] && [ "$NO_UI" != 1 ]; then
    if [ "$default" = yes ]; then read -r -p "$q [Y/n] " a </dev/tty || a=""; else read -r -p "$q [y/N] " a </dev/tty || a=""; fi
    case "${a:-$default}" in y|Y|yes|YES) return 0 ;; n|N|no|NO) return 1 ;; esac
    [ "$default" = yes ]
    return $?
  fi
  [ "$default" = yes ]
}

# ---------------------------------------------------------------------------
# Hardware detection. hardware.json tells Config/hardware-profile.nix which
# GPU driver to use and whether to turn on the laptop power bits.

# Display adapters (VGA or 3D controller) as "vendor address" lines, e.g.
# "nvidia 0000:01:00.0".
list_gpus() {
  local d cls vendor
  for d in /sys/bus/pci/devices/*; do
    cls="$(cat "$d/class" 2>/dev/null || true)"
    case "$cls" in 0x0300*|0x0302*|0x0380*) ;; *) continue ;; esac
    case "$(cat "$d/vendor" 2>/dev/null)" in
      0x10de) vendor=nvidia ;; 0x1002) vendor=amd ;; 0x8086) vendor=intel ;; *) continue ;;
    esac
    printf '%s %s\n' "$vendor" "${d##*/}"
  done
}
gpu_list="$(list_gpus)"
has_gpu() { printf '%s\n' "$gpu_list" | grep -q "^$1 "; }

# "0000:01:00.0" -> "PCI:1:0:0" (bus:device:function in decimal, as the
# NVIDIA driver wants it).
bus_id() {
  local addr="$1" bus dev fn
  [ -n "$addr" ] || return 0
  addr="${addr#*:}"; bus="${addr%%:*}"; addr="${addr#*:}"; dev="${addr%%.*}"; fn="${addr#*.}"
  printf 'PCI:%d:%d:%d\n' "0x$bus" "0x$dev" "0x$fn" 2>/dev/null || true
}
gpu_bus_id() { bus_id "$(printf '%s\n' "$gpu_list" | awk -v v="$1" '$1 == v { print $2; exit }')"; }

detect_gpu() {
  if has_gpu nvidia && { has_gpu intel || has_gpu amd; }; then
    echo hybrid                    # an iGPU next to a GeForce: PRIME
  elif has_gpu nvidia; then echo nvidia
  elif has_gpu amd; then echo amd
  elif has_gpu intel; then echo intel
  else echo amd
  fi
}
detect_igpu() { if has_gpu intel; then echo intel; else echo amd; fi; }

detect_cpu() {
  case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
    *GenuineIntel*) echo intel ;;
    *) echo amd ;;
  esac
}

detect_laptop() {
  local b
  for b in /sys/class/power_supply/BAT*; do [ -e "$b" ] && { echo 1; return; }; done
  case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
    8|9|10|11|14|31|32) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Defaults: the environment, then what an existing checkout already says,
# then detection.
read_hw() { # key -> value from an existing hardware.json, or nothing
  [ -f "$DIR/hardware.json" ] || return 0
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([a-z0-9]*\)\"\{0,1\}.*/\1/p" "$DIR/hardware.json" | head -1
}
GPU="${NIXOSCONF_GPU:-$(read_hw gpu)}";       [ -n "$GPU" ] || GPU="$(detect_gpu)"
CPU="${NIXOSCONF_CPU:-$(read_hw cpu)}";       [ -n "$CPU" ] || CPU="$(detect_cpu)"
LAPTOP="${NIXOSCONF_LAPTOP:-$(read_hw laptop)}"
case "$LAPTOP" in true|1) LAPTOP=1 ;; false|0) LAPTOP=0 ;; *) LAPTOP="$(detect_laptop)" ;; esac
IGPU="${NIXOSCONF_IGPU:-$(read_hw igpu)}";    [ -n "$IGPU" ] || IGPU="$(detect_igpu)"
PRIME="${NIXOSCONF_PRIME:-$(read_hw prime)}"; [ -n "$PRIME" ] || PRIME=offload
read_busid() { # igpu|nvidia -> value from an existing hardware.json
  [ -f "$DIR/hardware.json" ] || return 0
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\(PCI:[0-9:@]*\)\".*/\1/p" "$DIR/hardware.json" | head -1
}
IGPU_BUSID="${NIXOSCONF_IGPU_BUSID:-$(gpu_bus_id "$IGPU")}";    [ -n "$IGPU_BUSID" ] || IGPU_BUSID="$(read_busid igpu)"
NVIDIA_BUSID="${NIXOSCONF_NVIDIA_BUSID:-$(gpu_bus_id nvidia)}"; [ -n "$NVIDIA_BUSID" ] || NVIDIA_BUSID="$(read_busid nvidia)"
case "$GPU" in amd|nvidia|intel|hybrid) ;; *) die "NIXOSCONF_GPU must be amd, nvidia, intel or hybrid (got '$GPU')" ;; esac
case "$CPU" in amd|intel) ;; *) die "NIXOSCONF_CPU must be amd or intel (got '$CPU')" ;; esac
case "$IGPU" in amd|intel) ;; *) die "NIXOSCONF_IGPU must be intel or amd (got '$IGPU')" ;; esac
case "$PRIME" in offload|sync) ;; *) die "NIXOSCONF_PRIME must be offload or sync (got '$PRIME')" ;; esac

# Data drives: yes when a GD1/GD2 filesystem is visible or already mounted,
# otherwise yes on desktops and no on laptops. Home links follow the drives.
drives_visible() {
  local l
  for l in $DRIVES; do
    findmnt -n "/mnt/$l" >/dev/null 2>&1 && return 0
    [ -n "$(blkid -L "$l" 2>/dev/null)" ] && return 0
  done
  return 1
}
DATA_DRIVES="${NIXOSCONF_DRIVES:-$(read_hw dataDrives)}"
case "$DATA_DRIVES" in true|1) DATA_DRIVES=1 ;; false|0) DATA_DRIVES=0 ;;
  *) if drives_visible || [ "$LAPTOP" = 0 ]; then DATA_DRIVES=1; else DATA_DRIVES=0; fi ;; esac
HOME_LINKS="${NIXOSCONF_HOME_LINKS:-$(read_hw homeLinks)}"
case "$HOME_LINKS" in true|1) HOME_LINKS=1 ;; false|0) HOME_LINKS=0 ;; *) HOME_LINKS="$DATA_DRIVES" ;; esac
yn() { if [ "$1" = 1 ]; then echo yes; else echo no; fi; }

# One line describing the GPU choice, for the summary boxes.
gpu_desc() {
  if [ "$GPU" = hybrid ]; then
    echo "hybrid ($IGPU iGPU $IGPU_BUSID + NVIDIA $NVIDIA_BUSID, PRIME $PRIME)"
  else
    echo "$GPU"
  fi
}

# No commas in these: gum's --selected takes a comma-separated list.
gpu_opts=(
  "amd     Radeon: Mesa + amdgpu early KMS + overclocking + LACT"
  "nvidia  GeForce only: proprietary driver with NVIDIA's open kernel modules (Turing or newer)"
  "intel   Intel graphics: Mesa + media drivers + OpenCL"
  "hybrid  Laptop with an Intel/AMD iGPU and a GeForce: iGPU drives the screen + NVIDIA through PRIME"
)
igpu_opts=(
  "intel   Intel iGPU (Core / Core Ultra)"
  "amd     AMD iGPU (Ryzen APU)"
)
prime_opts=(
  "offload  Battery first: NVIDIA sleeps until a program uses it (Steam always does; nvidia-offload <app> for others)"
  "sync     Performance first: NVIDIA renders everything; the iGPU only drives the panel"
)
cpu_opts=(
  "amd     Ryzen / Threadripper microcode"
  "intel   Core / Xeon microcode (thermald on laptops)"
)
opt_for() { local k="$1"; shift; for o in "$@"; do [ "${o%% *}" = "$k" ] && { printf '%s\n' "$o"; return; }; done; }

# ask_text "prompt" "default" -> prints the answer
ask_text() {
  local a=""
  if [ -n "$GUM" ]; then
    a="$("$GUM" input --header "$1" --value "$2" --placeholder "PCI:1:0:0" </dev/tty 2>/dev/tty)" || a=""
  else
    read -r -p "$1 [$2]: " a </dev/tty || a=""
  fi
  printf '%s\n' "${a:-$2}"
}

box "nixosconf setup" \
  "Account   $USER_NAME ($FULL_NAME)" \
  "Config    $DIR  (branch $BRANCH)" \
  "Detected  GPU: $(gpu_desc)   CPU: $CPU   laptop: $(yn "$LAPTOP")" \
  "          data drives ($DRIVES): $(yn "$DATA_DRIVES")   home folder links: $(yn "$HOME_LINKS")"

if [ "$HAVE_TTY" = 1 ] && [ "$NO_UI" != 1 ]; then
  pick="$(choose "Graphics" "$(opt_for "$GPU" "${gpu_opts[@]}")" "${gpu_opts[@]}")"
  GPU="${pick%% *}"
  if [ "$GPU" = hybrid ]; then
    pick="$(choose "Which iGPU is next to the GeForce?" "$(opt_for "$IGPU" "${igpu_opts[@]}")" "${igpu_opts[@]}")"
    IGPU="${pick%% *}"
    [ -n "$IGPU_BUSID" ] && [ "$IGPU" = "$(detect_igpu)" ] || IGPU_BUSID="$(gpu_bus_id "$IGPU")"
    pick="$(choose "How should the NVIDIA GPU be used?" "$(opt_for "$PRIME" "${prime_opts[@]}")" "${prime_opts[@]}")"
    PRIME="${pick%% *}"
    if [ -z "$IGPU_BUSID" ] || [ -z "$NVIDIA_BUSID" ]; then
      {
        echo; echo "PRIME needs the PCI address of each GPU. Display adapters on this machine:"
        printf '%s\n' "$gpu_list" | while read -r v a; do
          if [ -n "$a" ]; then printf '  %-7s %s  -> %s\n' "$v" "$a" "$(bus_id "$a")"; else echo "  (none found; check lspci)"; fi
        done
        echo
      } >/dev/tty
    fi
    IGPU_BUSID="$(ask_text "$IGPU iGPU bus ID" "$IGPU_BUSID")"
    NVIDIA_BUSID="$(ask_text "NVIDIA GPU bus ID" "$NVIDIA_BUSID")"
  fi
  pick="$(choose "Processor" "$(opt_for "$CPU" "${cpu_opts[@]}")" "${cpu_opts[@]}")"
  CPU="${pick%% *}"
  if confirm "Is this a laptop? (power profiles, lid switch, Wi-Fi power saving)" "$(yn "$LAPTOP")"; then
    LAPTOP=1
  else
    LAPTOP=0
  fi
  if confirm "Mount the data drives $DRIVES at /mnt? (no: skip them entirely)" "$(yn "$DATA_DRIVES")"; then
    DATA_DRIVES=1
  else
    DATA_DRIVES=0
    HOME_LINKS=0
  fi
  if [ "$DATA_DRIVES" = 1 ]; then
    if confirm "Replace Documents, Downloads, Music, Pictures, Videos and .ssh with links into /mnt/GD2/Backup (plus the book libraries)?" "$(yn "$HOME_LINKS")"; then
      HOME_LINKS=1
    else
      HOME_LINKS=0
    fi
  fi
  box "Ready to install" \
    "GPU       $(gpu_desc)" \
    "CPU       $CPU" \
    "Laptop    $(yn "$LAPTOP")" \
    "Drives    $(yn "$DATA_DRIVES")   home folder links: $(yn "$HOME_LINKS")" \
    "" \
    "Next: clone the config, generate the hardware files, build and" \
    "switch (downloads several GB), install the Flatpaks, reboot."
  confirm "Start now?" yes || { say "Nothing changed."; exit 0; }
else
  say "No terminal for the setup UI; using GPU=$(gpu_desc) CPU=$CPU laptop=$LAPTOP drives=$DATA_DRIVES links=$HOME_LINKS (override with NIXOSCONF_GPU/CPU/LAPTOP/DRIVES/HOME_LINKS)"
fi
[ "$DATA_DRIVES" = 1 ] || HOME_LINKS=0
if [ "$GPU" = hybrid ] && { [ -z "$IGPU_BUSID" ] || [ -z "$NVIDIA_BUSID" ]; }; then
  die "A hybrid GPU needs both PCI bus IDs. Set NIXOSCONF_IGPU_BUSID and NIXOSCONF_NVIDIA_BUSID (PCI:bus:device:function, from lspci) or pick a single GPU."
fi

# ---------------------------------------------------------------------------
# 1. Clone or update the repo, as the user

fresh=0
if [ -d "$DIR/.git" ]; then
  origin="$(sudo -u "$USER_NAME" "$GIT" -C "$DIR" remote get-url origin 2>/dev/null || true)"
  [ "${origin%.git}" = "${REPO%.git}" ] \
    || die "$DIR is a checkout of '$origin', not '$REPO'. Move it aside or set NIXOSCONF_DIR."
  say "Updating existing checkout (branch $BRANCH)"
  as_user "$GIT" -C "$DIR" fetch origin "$BRANCH"
  as_user "$GIT" -C "$DIR" checkout "$BRANCH"
  as_user "$GIT" -C "$DIR" pull --ff-only --autostash origin "$BRANCH"
elif [ -e "$DIR" ]; then
  die "$DIR exists but is not a git checkout. Move it aside or set NIXOSCONF_DIR."
else
  say "Cloning $REPO (branch $BRANCH)"
  as_user "$GIT" clone --branch "$BRANCH" "$REPO" "$DIR"
  fresh=1
fi

# ---------------------------------------------------------------------------
# 2. user.nix: build the config for this account

say "Writing user.nix for $USER_NAME"
write_as_user "$DIR/user.nix" <<NIX
# The account this configuration is built for. setup.sh rewrites this with
# whatever account it is run from.
{
  name = "$USER_NAME";
  fullName = "$FULL_NAME";
}
NIX

tf() { if [ "$1" = 1 ]; then echo true; else echo false; fi; }
say "Writing hardware.json (gpu=$(gpu_desc) cpu=$CPU laptop=$LAPTOP drives=$DATA_DRIVES links=$HOME_LINKS)"
if [ "$GPU" = hybrid ]; then
  write_as_user "$DIR/hardware.json" <<JSON
{
  "cpu": "$CPU",
  "gpu": "hybrid",
  "igpu": "$IGPU",
  "prime": "$PRIME",
  "busIds": {
    "igpu": "$IGPU_BUSID",
    "nvidia": "$NVIDIA_BUSID"
  },
  "laptop": $(tf "$LAPTOP"),
  "dataDrives": $(tf "$DATA_DRIVES"),
  "homeLinks": $(tf "$HOME_LINKS")
}
JSON
else
  write_as_user "$DIR/hardware.json" <<JSON
{
  "cpu": "$CPU",
  "gpu": "$GPU",
  "laptop": $(tf "$LAPTOP"),
  "dataDrives": $(tf "$DATA_DRIVES"),
  "homeLinks": $(tf "$HOME_LINKS")
}
JSON
fi

# ---------------------------------------------------------------------------
# 3. hardware-configuration.nix and drives.nix for this machine

# Find the partition for /mnt/<label>. Tries, in order: whatever is mounted
# there now, a filesystem labelled <label>, the UUID the repo already knows,
# and finally asks. Prints "<uuid> <fstype>" or nothing.
find_drive() {
  local label="$1" dev="" uuid="" fstype=""
  dev="$(findmnt -n -o SOURCE "/mnt/$label" 2>/dev/null || true)"
  [ -n "$dev" ] || dev="$(blkid -L "$label" 2>/dev/null || true)"
  if [ -z "$dev" ] && [ -f "$DIR/drives.nix" ]; then
    uuid="$(grep -A1 "\"/mnt/$label\"" "$DIR/drives.nix" | grep -o 'by-uuid/[0-9A-Fa-f-]*' | cut -d/ -f2 || true)"
    [ -n "$uuid" ] && dev="$(blkid -U "$uuid" 2>/dev/null || true)"
  fi
  if [ -z "$dev" ] && [ "$HAVE_TTY" = 1 ] && [ "$NO_UI" != 1 ]; then
    local parts=() line skip="skip: no /mnt/$label on this machine"
    while IFS= read -r line; do parts+=("$line"); done \
      < <(lsblk -rpno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | awk -F'[ ]' '$3 != "" && $3 != "swap"' || true)
    if [ -n "$GUM" ] && [ "${#parts[@]}" -gt 0 ]; then
      line="$(choose "Which partition is /mnt/$label?" "$skip" "${parts[@]}" "$skip")"
      [ "$line" = "$skip" ] && dev="" || dev="${line%% *}"
    else
      {
        echo
        echo "Could not find the drive for /mnt/$label. Partitions on this machine:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT 2>/dev/null || true
        echo
      } >/dev/tty
      read -r -p "Device for /mnt/$label (e.g. /dev/sdb1, blank to skip): " dev </dev/tty
    fi
  fi
  [ -n "$dev" ] || return 0
  uuid="$(blkid -s UUID -o value "$dev" 2>/dev/null || true)"
  fstype="$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)"
  if [ -z "$uuid" ] || [ -z "$fstype" ]; then
    warn "Could not read a UUID and filesystem type from $dev, skipping /mnt/$label"
    return 0
  fi
  printf '%s %s\n' "$uuid" "$fstype"
}

write_drives_nix() { # entries on stdin
  write_as_user "$DIR/drives.nix" <<NIX
# Extra data drives. setup.sh regenerates this file after finding the drives
# on the machine, so edit it by hand only if the detection got it wrong.
# dataDrives = false in hardware.json turns the mounts off without editing.
{ lib, ... }:
lib.mkIf (({ dataDrives = true; } // builtins.fromJSON (builtins.readFile ./hardware.json)).dataDrives) {$(cat)
}
NIX
}

if [ "$fresh" = 1 ] || [ "${NIXOSCONF_REGEN_HARDWARE:-0}" = 1 ] || [ ! -f "$DIR/hardware-configuration.nix" ]; then
  say "Generating hardware-configuration.nix for this machine"
  if [ "$DRY_RUN" = 1 ]; then
    run "nixos-generate-config --show-hardware-config > $DIR/hardware-configuration.nix"
  else
    nixos-generate-config --show-hardware-config | write_as_user "$DIR/hardware-configuration.nix"
  fi
else
  say "Keeping the existing hardware-configuration.nix (NIXOSCONF_REGEN_HARDWARE=1 to redo)"
fi

if [ "$DATA_DRIVES" = 0 ]; then
  say "Data drives turned off; writing an empty drives.nix"
  write_drives_nix </dev/null
elif [ "$fresh" = 1 ] || [ "${NIXOSCONF_REGEN_HARDWARE:-0}" = 1 ] || ! grep -q 'fileSystems\."/mnt/' "$DIR/drives.nix" 2>/dev/null; then
  say "Looking for the data drives ($DRIVES)"
  entries=""
  for label in $DRIVES; do
    found="$(find_drive "$label")"
    if [ -z "$found" ]; then
      warn "/mnt/$label not configured; rerun with NIXOSCONF_REGEN_HARDWARE=1 or edit drives.nix"
      continue
    fi
    uuid="${found% *}"; fstype="${found#* }"
    say "/mnt/$label -> UUID $uuid ($fstype)"
    entries="$entries
  fileSystems.\"/mnt/$label\" = {
    device = \"/dev/disk/by-uuid/$uuid\";
    fsType = \"$fstype\";
    options = [ \"nofail\" ];
  };"
  done
  printf '%s' "$entries" | write_drives_nix
else
  say "Keeping the existing drives.nix (NIXOSCONF_REGEN_HARDWARE=1 to redo)"
fi

# Mount the data drives now rather than after the reboot, so the first build
# can already link the home folders into /mnt/GD2/Backup.
if [ "$DATA_DRIVES" = 1 ] && [ -f "$DIR/drives.nix" ]; then
  while read -r mnt uuid; do
    [ -n "$mnt" ] && [ -n "$uuid" ] || continue
    if mountpoint -q "$mnt" 2>/dev/null; then
      say "$mnt is already mounted"
    else
      say "Mounting $mnt"
      run mkdir -p "$mnt"
      run mount "UUID=$uuid" "$mnt" || warn "Could not mount $mnt now; it will be mounted after the reboot"
    fi
  done < <(awk '/fileSystems\."\/mnt\// { gsub(/.*fileSystems\."|".*/, ""); m=$0 } /by-uuid/ { gsub(/.*by-uuid\/|".*/, ""); print m, $0 }' "$DIR/drives.nix")
fi

# ---------------------------------------------------------------------------
# 4. /etc/nixos -> the checkout

if [ "$DIR" != "$LINK" ]; then
  if [ -L "$LINK" ] && [ "$(readlink -f "$LINK")" = "$(readlink -f "$DIR" 2>/dev/null || echo "$DIR")" ]; then
    say "$LINK already points at $DIR"
  else
    if [ -e "$LINK" ] || [ -L "$LINK" ]; then
      backup="${LINK}.bak-$(date +%Y%m%d-%H%M%S)"
      say "Moving the current $LINK to $backup"
      run mv "$LINK" "$backup"
    fi
    say "Linking $LINK -> $DIR"
    run ln -s "$DIR" "$LINK"
  fi
fi

# nix refuses to read a git repo owned by someone else unless it is marked
# safe, and root reads the user's checkout during nixos-rebuild. The system
# config takes care of this once it is applied; for the first build root's own
# gitconfig has to do it, so run the build with HOME=/root.
# libgit2 matches safe.directory against the resolved path of the repo.
real_dir="$(readlink -f "$DIR" 2>/dev/null || echo "$DIR")"
if ! "$GIT" config --file /root/.gitconfig --get-all safe.directory 2>/dev/null | grep -qx "$real_dir"; then
  run "$GIT" config --file /root/.gitconfig --add safe.directory "$real_dir"
fi

# ---------------------------------------------------------------------------
# 5. Build and switch

say "Building and switching to the new system (the first run downloads several GB)"
run env HOME=/root nixos-rebuild switch --flake "${LINK}#${FLAKE_HOST}"

# ---------------------------------------------------------------------------
# 6. Flatpaks

# home-manager's user service installs them at the next login. Run that same
# script now so everything is in place after the reboot.
unit="$HOME_DIR/.config/systemd/user/flatpak-managed-install.service"
if [ "$DRY_RUN" = 1 ]; then
  run "<ExecStart of $unit, as $USER_NAME>"
elif [ -f "$unit" ]; then
  read -r -a installer <<<"$(sed -n 's/^ExecStart=//p' "$unit" | head -1)"
  say "Installing the Flatpaks from Apps/flatpaks.nix (this is the slow part)"
  sudo -u "$USER_NAME" -H env XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" "${installer[@]}" \
    || warn "Flatpak install did not finish; it runs again at login and on the next update"
else
  warn "Flatpak installer not found; the Flatpaks will be installed at the next login"
fi

# ---------------------------------------------------------------------------
# 7. Reboot

say "Done."
box "All set" \
  "Config    $DIR  (branch $BRANCH), reachable as $LINK" \
  "Hardware  GPU: $(gpu_desc)   CPU: $CPU   laptop: $(yn "$LAPTOP")" \
  "Drives    $(yn "$DATA_DRIVES")   home folder links: $(yn "$HOME_LINKS")" \
  "Update    nixos-updater, or the NixOS Updater app in the start menu" \
  "Rebuild   sudo nixos-rebuild switch --flake $LINK"

if [ "${NIXOSCONF_NO_REBOOT:-0}" = 1 ]; then
  say "Reboot to finish (new kernel, scheduler and drivers)."
elif [ "$DRY_RUN" = 1 ]; then
  run reboot
elif [ -n "$GUM" ]; then
  if confirm "Reboot now into the new system? (new kernel, scheduler and drivers)" yes; then
    reboot
  else
    say "Reboot when you are ready."
  fi
else
  say "Rebooting in 15 seconds into the new system (Ctrl-C to stay)."
  sleep 15
  reboot
fi
