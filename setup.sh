#!/usr/bin/env bash
#
# Set up this machine to use the nixosconf flake. Run it from your normal
# account with sudo:
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
#
# It uses the account that ran sudo, clones the repo into that account's home,
# points /etc/nixos at the clone, writes user.nix, hardware-configuration.nix
# and drives.nix for this machine, and switches to the new system.
#
# Environment overrides:
#   NIXOSCONF_BRANCH            branch to check out        (default: main)
#   NIXOSCONF_DIR               where to clone             (default: ~/nixosconf)
#   NIXOSCONF_REPO              git URL of the config repo
#   NIXOSCONF_USER              account to set up          (default: the sudo user)
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
  if [ -z "$dev" ] && { : </dev/tty; } 2>/dev/null; then
    {
      echo
      echo "Could not find the drive for /mnt/$label. Partitions on this machine:"
      lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT 2>/dev/null || true
      echo
    } >/dev/tty
    read -r -p "Device for /mnt/$label (e.g. /dev/sdb1, blank to skip): " dev </dev/tty
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

if [ "$fresh" = 1 ] || [ "${NIXOSCONF_REGEN_HARDWARE:-0}" = 1 ] || [ ! -f "$DIR/hardware-configuration.nix" ]; then
  say "Generating hardware-configuration.nix for this machine"
  if [ "$DRY_RUN" = 1 ]; then
    run "nixos-generate-config --show-hardware-config > $DIR/hardware-configuration.nix"
  else
    nixos-generate-config --show-hardware-config | write_as_user "$DIR/hardware-configuration.nix"
  fi

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
  write_as_user "$DIR/drives.nix" <<NIX
# Extra data drives. setup.sh regenerates this file after finding the drives
# on the machine, so edit it by hand only if the detection got it wrong.
{ ... }:
{$entries
}
NIX
else
  say "Keeping the existing hardware-configuration.nix and drives.nix (NIXOSCONF_REGEN_HARDWARE=1 to redo)"
fi

# Mount the data drives now rather than after the reboot, so the first build
# can already link the home folders into /mnt/GD2/Backup.
if [ -f "$DIR/drives.nix" ]; then
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
    || warn "Flatpak install did not finish; it runs again at login and on the next topgrade"
else
  warn "Flatpak installer not found; the Flatpaks will be installed at the next login"
fi

# ---------------------------------------------------------------------------
# 7. Reboot

say "Done."
cat <<MSG

  Config:    $DIR  (branch $BRANCH), reachable as $LINK
  Update:    topgrade          (refreshes flake inputs, rebuilds, updates flatpaks)
  Rebuild:   sudo nixos-rebuild switch --flake $LINK

MSG

if [ "${NIXOSCONF_NO_REBOOT:-0}" = 1 ]; then
  say "Reboot to finish (new kernel, scheduler and drivers)."
elif [ "$DRY_RUN" = 1 ]; then
  run reboot
else
  say "Rebooting in 15 seconds into the new system (Ctrl-C to stay)."
  sleep 15
  reboot
fi
