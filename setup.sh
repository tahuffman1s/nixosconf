#!/usr/bin/env bash
#
# Set up this machine to use the nixosconf flake.
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
#
# Environment overrides:
#   NIXOSCONF_BRANCH   branch to check out            (default: main)
#   NIXOSCONF_DIR      where the config lives          (default: /etc/nixos)
#   NIXOSCONF_REPO     git URL of the config repo
#   DRY_RUN=1          print the privileged steps instead of running them
#
# What it does:
#   1. backs up the current config dir to <dir>.bak-<timestamp>
#   2. clones (or updates) the repo into the config dir
#   3. keeps this machine's hardware-configuration.nix, generating one if
#      there is none
#   4. runs `nixos-rebuild switch --flake <dir>#nixos`
#   5. sets a password for the user if the account did not exist before

set -euo pipefail

REPO="${NIXOSCONF_REPO:-https://github.com/tahuffman1s/nixosconf.git}"
BRANCH="${NIXOSCONF_BRANCH:-main}"
DIR="${NIXOSCONF_DIR:-/etc/nixos}"
USER_NAME="travis"          # must match Config/users.nix and Home/settings.nix
FLAKE_HOST="nixos"          # must match nixosConfigurations.<name> in flake.nix
DRY_RUN="${DRY_RUN:-0}"

export NIX_CONFIG="experimental-features = nix-command flakes"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# Privileged / state-changing steps go through here so DRY_RUN can show them.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '   + %s\n' "$*"
  else
    "$@"
  fi
}

# git is not installed on a fresh NixOS; borrow it from nixpkgs if needed.
git_cmd() {
  if command -v git >/dev/null 2>&1; then
    git "$@"
  else
    nix shell nixpkgs#git -c git "$@"
  fi
}

# ---------------------------------------------------------------------------

[ -e /etc/NIXOS ] || [ "$DRY_RUN" = 1 ] || die "This only works on NixOS."

if [ "$(id -u)" -ne 0 ]; then
  die "Run this as root, e.g.:
  curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/${BRANCH}/setup.sh | sudo bash"
fi

user_existed=0
id "$USER_NAME" >/dev/null 2>&1 && user_existed=1

# 1. Back up whatever is there now --------------------------------------------
hw_backup=""
if [ -d "$DIR" ] && [ ! -d "$DIR/.git" ]; then
  backup="${DIR}.bak-$(date +%Y%m%d-%H%M%S)"
  say "Backing up $DIR to $backup"
  [ -f "$DIR/hardware-configuration.nix" ] && hw_backup="$backup/hardware-configuration.nix"
  run mv "$DIR" "$backup"
fi

# 2. Clone or update the repo ---------------------------------------------------
if [ -d "$DIR/.git" ]; then
  origin="$(git_cmd -C "$DIR" remote get-url origin 2>/dev/null || true)"
  if [ "${origin%.git}" != "${REPO%.git}" ]; then
    die "$DIR is a git checkout of '$origin', not '$REPO'. Move it aside and rerun."
  fi
  say "Updating existing checkout in $DIR (branch $BRANCH)"
  run git_cmd -C "$DIR" fetch origin "$BRANCH"
  run git_cmd -C "$DIR" checkout "$BRANCH"
  run git_cmd -C "$DIR" pull --ff-only --autostash origin "$BRANCH"
else
  say "Cloning $REPO (branch $BRANCH) into $DIR"
  run git_cmd clone --branch "$BRANCH" "$REPO" "$DIR"
fi

# 3. Hardware configuration -----------------------------------------------------
# The repo tracks the hardware-configuration.nix of the machine it was written
# on. This machine's own copy always wins; generate one if there is none.
if [ -n "$hw_backup" ]; then
  say "Keeping this machine's hardware-configuration.nix from the backup"
  run cp "$hw_backup" "$DIR/hardware-configuration.nix"
elif [ ! -f "$DIR/hardware-configuration.nix" ] || [ "$DRY_RUN" = 1 ]; then
  say "Generating hardware-configuration.nix for this machine"
  if [ "$DRY_RUN" = 1 ]; then
    run "nixos-generate-config --show-hardware-config > $DIR/hardware-configuration.nix"
  else
    nixos-generate-config --show-hardware-config > "$DIR/hardware-configuration.nix"
  fi
else
  warn "Using the hardware-configuration.nix that ships in the repo."
  warn "If this is not the machine it was generated on, run:"
  warn "  sudo nixos-generate-config --show-hardware-config > $DIR/hardware-configuration.nix"
fi

# 4. Make the checkout editable by the user ------------------------------------
# The fish aliases open files in $DIR with codium as $USER_NAME.
if [ "$user_existed" = 1 ]; then
  say "Giving $USER_NAME ownership of $DIR"
  run chown -R "$USER_NAME" "$DIR"
fi
run git_cmd config --global --add safe.directory "$DIR"

# 5. Build and switch -----------------------------------------------------------
say "Building and switching to the new system (first run downloads several GB)"
run nixos-rebuild switch --flake "${DIR}#${FLAKE_HOST}"

if [ "$user_existed" = 0 ]; then
  say "Giving $USER_NAME ownership of $DIR"
  run chown -R "$USER_NAME" "$DIR"
  if [ "$DRY_RUN" = 1 ]; then
    run "passwd $USER_NAME"
  elif [ -r /dev/tty ]; then
    say "User $USER_NAME was just created. Set a password for it:"
    passwd "$USER_NAME" </dev/tty
  else
    warn "User $USER_NAME was just created but has no password. Run: sudo passwd $USER_NAME"
  fi
fi

say "Done."
cat <<MSG

  Config:   $DIR  (branch $BRANCH)
  Rebuild:  sudo nixos-rebuild switch --flake $DIR#$FLAKE_HOST
  Update:   cd $DIR && sudo nix flake update && sudo nixos-rebuild switch --flake .

  Flatpaks from Apps/flatpaks.nix are installed by a user service the first
  time $USER_NAME logs in to the new system (it needs network access).
  Home folders are only linked into /mnt/GD2/Backup when that drive is mounted.
MSG
