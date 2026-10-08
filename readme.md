# nixosconf

NixOS flake for my desktop: Plasma 6 on nixos-unstable, home-manager, Flatpaks
from Flathub managed with nix-flatpak, Bazaar as the app store, Dracula theme
everywhere.

## Setup

On a NixOS machine, from your own account:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
```

The script builds the config for the account that ran `sudo`. It clones this
repo into `~/nixosconf` (owned by you), points `/etc/nixos` at it, writes
`user.nix` with your account name, generates `hardware-configuration.nix`, finds
the GD1 and GD2 drives for `drives.nix` (by current mount, filesystem label,
known UUID, or by asking), and runs `nixos-rebuild switch --flake /etc/nixos`.
Rerunning it on a machine that already has the clone just pulls and switches.

To use a branch other than `main`:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo NIXOSCONF_BRANCH=some-branch bash
```

## Day to day

```sh
topgrade                                       # or `update` in fish
sudo nixos-rebuild switch --flake /etc/nixos   # or `swap` in fish, after editing
```

topgrade is configured in `Apps/topgrade.nix`: it refreshes `flake.lock`,
runs `nixos-rebuild switch --flake /etc/nixos`, then updates the Flatpaks.

## Layout

| Path | What |
| --- | --- |
| `flake.nix` | Inputs and the `nixos` system definition |
| `user.nix` | The account the config is built for (written by setup.sh) |
| `drives.nix` | GD1 and GD2 mounts (written by setup.sh) |
| `configuration.nix` | System module list |
| `Config/` | Boot, hardware, networking, locale, services, users, nix settings |
| `Apps/` | Per-app modules (Steam, kitty, fish, VSCodium, Flatpak list, ...) |
| `Home/` | home-manager entry point, native packages, home folder links |
| `Theme/` | Plasma and GTK theming |
| `Files/` | Theme archives unpacked at build time |

`Home/links.nix` replaces Documents, Downloads, Music, Pictures, Videos and
`.ssh` with symlinks into `/mnt/GD2/Backup`, and links the book libraries from
`/mnt/GD2/Backup/Books`. It only acts when that drive is mounted.
