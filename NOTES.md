# Install Notes

To save the config to persistent storage, mount a USB drive:

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb;
```

You can use that same medium to replicate the installation by runn from the usb stick

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb && archinstall --config /mnt/usb/dotfiles-arch/user_configuration.json --creds /mnt/usb/dotfiles-arch/user_credentials.json;
```

Alternately, you can leverage the presaved file on http://archconfig.weekendproject.app/

```shell
archinstall --config-url http://archconfig.weekendproject.app/
```

You need to set:
- Disk Configuration
- Hostname
- Authentication


You can get some extra information about what drives were inserted using `dmesg`

You can unmount via `umount /mnt/usb`



To get Arch up and running into Hyperland run:
./post_install.sh

