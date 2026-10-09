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

The other tabs edit parts of the config that describe this machine. Each
Save commits; Apply (or Update) rebuilds:

| Tab | File | What |
| --- | --- | --- |
| Autostart | `Home/autostart.json` | Apps and commands started with the Plasma session |
| Shortcuts | `Home/shortcuts.json` | Global shortcuts that run a command (plasma-manager hotkeys) |
| Services | `Config/services.json` | On/off switches for SSH, KDE Connect, Tailscale, Syncthing, Docker, libvirt, Sunshine, Jellyfin, fwupd, Ollama; the NixOS side of each lives in `Config/services-toggles.nix` |
| Auto Updates | `Config/autoupdate.json` | A systemd timer that refreshes inputs, rebuilds (for next boot or immediately), updates Flatpaks, and can reboot when the kernel changed |

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
| `Home/autostart.json`, `Home/shortcuts.json`, `Config/services.json`, `Config/autoupdate.json` | Edited by the updater's tabs |
| `Home/` | home-manager entry point, native packages, home folder links |
| `Theme/` | Plasma and GTK theming |
| `Files/` | Theme archives unpacked at build time |

`Home/links.nix` replaces Documents, Downloads, Music, Pictures, Videos and
`.ssh` with symlinks into `/mnt/GD2/Backup`, and links the book libraries from
`/mnt/GD2/Backup/Books`. It only acts when that drive is mounted.
