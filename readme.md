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
config for the account that ran `sudo`. It clones this repo into `~/nixosconf`
(owned by you), points `/etc/nixos` at it, writes `user.nix` with your account
name, generates `hardware-configuration.nix`, finds the GD1 and GD2 drives for
`drives.nix` (by current mount, filesystem label, known UUID, or by asking) and
mounts them, runs `nixos-rebuild switch --flake /etc/nixos`, installs the
Flatpaks, and reboots into the new system. Files that home-manager wants to
own are moved aside with an `.hm-backup` suffix rather than stopping the build.
Rerunning it on a machine that already has the clone just pulls and switches.
Set `NIXOSCONF_NO_REBOOT=1` to skip the reboot.

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
| Flatpaks | `Apps/flatpaks.json` | What the config declares; Sync records installs, removals and permission changes |
| Autostart | `Home/autostart.json` | Apps and commands started with the Plasma session, with a picker over installed apps |
| Shortcuts | `Home/shortcuts.json` | Global shortcuts that run a command (plasma-manager hotkeys), recorded with a key editor |
| System Units | `Config/units.json`, `Config/units/` | systemd units for the whole machine: drop `.service`/`.timer` files, or create a timer from a name, command and schedule |
| User Units | same | The same for home-manager units that run as you inside your session |
| Scripts | `Home/scripts.json`, `Home/scripts/` | Bash or Python scripts plus companion files; installed to `~/.local/share/nixos-scripts/` and scripts onto PATH via `~/.local/bin`; Run and Edit buttons; the timer wizard can pick one; scripts ticked "After update" run at the end of every Update or Apply, attended or not; "As root" runs a script with root rights, from the copy the system build installs under `/etc/nixos-scripts/` |
| Auto Updates | `Config/autoupdate.json` | A systemd timer that refreshes inputs, rebuilds (for next boot or immediately), updates Flatpaks, and can reboot when the kernel changed |

Terminal equivalents: `nixos-updater unit add|remove|list` and
`nixos-updater script add|remove|run|list`.

## Layout

| Path | What |
| --- | --- |
| `flake.nix` | Inputs and the `nixos` system definition |
| `user.nix` | The account the config is built for (written by setup.sh) |
| `drives.nix` | GD1 and GD2 mounts (written by setup.sh) |
| `configuration.nix` | System module list |
| `Config/` | Boot, hardware, networking, locale, services, users, nix settings |
| `Apps/` | Per-app modules (Steam, kitty, fish, VSCodium, Zen, the updater app, ...) |
| `Apps/flatpaks.json` | Installed Flatpaks and their permissions, kept in sync by the updater |
| `Home/autostart.json`, `Home/shortcuts.json`, `Home/scripts.json` + `Home/scripts/`, `Config/units.json` + `Config/units/`, `Config/autoupdate.json` | Edited by the updater's pages |
| `Home/` | home-manager entry point, native packages, home folder links |
| `Theme/` | Plasma and GTK theming |
| `Files/` | Theme archives unpacked at build time |

`Home/links.nix` replaces Documents, Downloads, Music, Pictures, Videos and
`.ssh` with symlinks into `/mnt/GD2/Backup`, and links the book libraries from
`/mnt/GD2/Backup/Books`. It only acts when that drive is mounted.
