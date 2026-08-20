#!/bin/bash -eux

# This script is based on instructions from
# - https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS#Create_a_custom_ISO
# - https://wiki.archlinux.org/title/Archiso

# List of required packages to create an ZFS ISO image (to be installed in the docker container)
PACKAGES=( archiso )
pacman --noconfirm -Syu "${PACKAGES[@]}"

# From the wiki on archiso:
# > Archiso comes with two profiles, releng and baseline.
# > * releng is used to create the official monthly installation ISO. It can be used as a starting point for
# >   creating a customized ISO image.
# > * baseline is a minimal configuration, that includes only the bare minimum packages required to boot the
# >   live environment from the medium.
ORIGIN_PROFILE="releng"

# We will work on a copy of the origin profile.
ZFS_PROFILE="zfs-archiso"
rm -rf "$ZFS_PROFILE"
cp -r "/usr/share/archiso/configs/$ORIGIN_PROFILE" "$ZFS_PROFILE"

# File "packages.x86_64" contains a list of packages available on the resulting ISO image. These are not
# automatically installed when using the ISO image to install arch linux. No need to worry about clutter here.
# We are going to replace the kernel package "linux" with "linux-lts", which is less likely to break when
# combined with ZFS. We are also going to install the zfs-utils (containing the zpool and zfs programs),
# libunwind (which zpool and zfs depend on), and zfs-dkms (Dynamic Kernel Module Support) which compiles the
# ZFS kernel module and also recompiles it automatically upon updating the kernel.

# You can later install linux and linux-lts alongside each other and pick the kernel when booting your system
# (for example using GRUB). This allows you to use the latest linux kernel, but fall back to the lts kernel if
# ZFS is broken on the latest kernel.

# For the ISO file we are just going to install linux-lts.

# First, let's remove linux from the package list.
sed -i '/^linux$/d' "$ZFS_PROFILE/packages.x86_64"

# Package broadcom-wl depends on linux and is included in the releng profile by default. We change it to
# broadcom-wl-dkms, so that the package is built for linux-lts instead.
sed -i 's/^broadcom-wl$/broadcom-wl-dkms/' "$ZFS_PROFILE/packages.x86_64"

# Add linux-lts and linux-lts-headers (headers are required for DKMS) as well as ZFS.
cat << EOF >> "$ZFS_PROFILE/packages.x86_64"
linux-lts
linux-lts-headers
libunwind
zfs-utils
zfs-dkms
EOF

# Archiso provides a mkinitcpio preset for linux (etc/mkinitcpio.d/linux.preset).
# From the wiki on mkinitcpio:
# > Every time a kernel is installed or upgraded, a pacman hook automatically generates a .preset file for
# > the kernel in /etc/mkinitcpio.d if one does not already exist.
# TODO: presumiably the file is newly generated when running mkarchiso?
rm "$ZFS_PROFILE/airootfs/etc/mkinitcpio.d/linux.preset"

# Append ArchZFS server to pacman config (this is the pacman config used to build the image?)
# TODO: GPG key
cat << EOF >> "$ZFS_PROFILE/pacman.conf"
[archzfs]
Server = https://github.com/archzfs/archzfs/releases/download/experimental
SigLevel = Never
EOF

# Edit the boot loader configuration files:
# * change vmlinuz-linux => vmlinuz-linux-lts
# * change initramfs-linux.img => initramfs-linux-lts.img
sed -i -E 's/(vmlinuz|initramfs)-linux/&-lts/g' "$ZFS_PROFILE"/efiboot/loader/entries/*.conf "$ZFS_PROFILE"/syslinux/*.cfg "$ZFS_PROFILE"/grub/*.cfg

# TODO: document options
rm -rf /tmp/archiso-tmp
mkarchiso -v -r -w /tmp/archiso-tmp -o build "$ZFS_PROFILE"

echo "finished!"
