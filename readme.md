# nixosconf

NixOS flake for my desktop: Plasma 6 on nixos-unstable, home-manager, Flatpaks
from Flathub managed with nix-flatpak, Bazaar as the app store, Dracula theme
everywhere.

## Setup

On a NixOS machine:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo bash
```

The script backs up `/etc/nixos`, clones this repo there, keeps the machine's
own `hardware-configuration.nix` (or generates one), and runs
`nixos-rebuild switch --flake /etc/nixos#nixos`. If the `travis` user did not
exist yet it asks for a password at the end. Rerunning the script on a machine
that already has the checkout just pulls and switches.

To try a branch other than `main`:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/nixosconf/main/setup.sh | sudo NIXOSCONF_BRANCH=some-branch bash
```

## Day to day

```sh
sudo nixos-rebuild switch --flake /etc/nixos          # apply changes
cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .   # update inputs
```

The fish shell has aliases for these (`swap`, `update`, `flake`, `conf`, `home`).

## Layout

| Path | What |
| --- | --- |
| `flake.nix` | Inputs and the `nixos` system definition |
| `configuration.nix` | System module list |
| `Config/` | Boot, hardware, networking, locale, services, users, nix settings |
| `Apps/` | Per-app modules (Steam, kitty, fish, VSCodium, Flatpak list, ...) |
| `Home/` | home-manager entry point, native packages, home folder links |
| `Theme/` | Plasma and GTK theming |
| `Files/` | Theme archives unpacked at build time |

`Home/links.nix` replaces Documents, Downloads, Music, Pictures, Videos and
`.ssh` with symlinks into `/mnt/GD2/Backup`, and links the book libraries from
`/mnt/GD2/Backup/Books`. It only acts when that drive is mounted.
