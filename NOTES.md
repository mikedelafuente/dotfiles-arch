# Install Notes

Target ISO: [archlinux-2026.07.01](https://fastly.mirror.pkgbuild.com/iso/2026.07.01/) (ships **archinstall 4.4**).
`user_configuration.json` is written for that schema (`bootloader_config`, `pacman_config`, zram `swap` object, nested `disk_encryption`).

## WiFi (before archinstall)

The live ISO needs network access before you can run `archinstall` or fetch configs. On WiFi:

```shell
# List interfaces (look for wlan0, wlp*, etc.)
ip link

# Enable the interface if it is down
ip link set wlan0 up

# Connect with iwctl (default on the Arch ISO)
iwctl
```

Inside `iwctl`:

```shell
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YourSSID"
exit
```

Confirm connectivity:

```shell
ping -c 3 archlinux.org
```

If DHCP did not assign an address:

```shell
dhcpcd wlan0
# or
systemctl start iwd
iwctl station wlan0 connect "YourSSID"
```

Wired Ethernet usually works without setup (`dhcpcd` / NetworkManager on the ISO). Prefer Ethernet when available.

## Config on USB

To save the config to persistent storage, mount a USB drive:

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb;
```

You can use that same medium to replicate the installation from the USB stick:

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb && archinstall --config /mnt/usb/dotfiles-arch/user_configuration.json --creds /mnt/usb/dotfiles-arch/user_credentials.json;
```

Alternately, you can leverage the presaved file on http://archconfig.weekendproject.app/

```shell
archinstall --config-url http://archconfig.weekendproject.app/
```

You need to set:

- Disk device path in `user_configuration.json` (`disk_config.device_modifications[0].device`)
- Hostname
- Authentication (including the LUKS encryption password in credentials)

## Disk layout (preconfigured)

`user_configuration.json` uses archinstall's default single-disk layout with:

- **Filesystem**: btrfs on the root partition, FAT32 EFI at `/boot` (1 GiB)
- **Subvolumes**: `@` (/), `@home` (/home), `@log` (/var/log), `@pkg` (/var/cache/pacman/pkg)
- **Snapshots**: Snapper
- **Encryption**: LUKS on the root/btrfs partition

Before installing, set `device` to your target disk (e.g. `/dev/nvme0n1` or `/dev/sda`). Confirm with `lsblk` / `dmesg`. The layout wipes the selected disk.

You can get some extra information about what drives were inserted using `dmesg`

You can unmount via `umount /mnt/usb`

## After install

GNOME + GDM are installed by archinstall. For NVIDIA drivers, Kitty, and multilib:

```shell
./post_install.sh
```

Then run bootstrap for the rest of the tooling. You will be prompted for a profile:

- **work** — shared stack + Zoom + Slack + Chrome
- **personal** — shared stack + Steam + Discord + Firefox + Mullvad

Everything else (Kitty, Cursor, Claude, Herdr, languages, containers, Spotify, Obsidian, etc.) is shared. Mullvad is personal-only; browsers are profile-specific (Chrome / Firefox).

```shell
bash scripts/bootstrap.sh
```

## Syncing an existing machine (drift / other PCs)

After big repo changes, bring a machine up to date without reinstalling Arch:

```shell
cd /path/to/dotfiles-arch
bash scripts/sync.sh
```

That will:

1. `git pull --ff-only` (if this is a git clone)
2. Re-run the setup scripts (idempotent installs for Kitty, Herdr, Cursor, Claude, …)
3. Relink dotfiles
4. Optionally remove obsolete packages (`tmux`, `ghostty`, `alacritty`, Hyprland stack, Copilot CLI) and stale configs

Useful flags:

```shell
bash scripts/sync.sh --profile work
bash scripts/sync.sh --profile personal
bash scripts/sync.sh --cleanup          # remove obsolete packages
bash scripts/sync.sh --skip-bootstrap   # only pull + link (+ optional cleanup)
bash scripts/sync.sh --yes --profile work --cleanup
```

If no profile is saved yet, sync prompts you to choose **work** or **personal** (with `--yes`, you must pass `--profile`).

Do this on each machine that should match the repo. Fresh installs still use `bootstrap.sh`.
