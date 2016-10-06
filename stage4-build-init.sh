#!/bin/bash -
# Init script installed in stage3 disk image.

# Set up the PATH.
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

# Root filesystem is mounted as ro, remount it as rw.
mount -o remount,rw /

# Mount standard filesystems.
mount -t proc /proc /proc
mount -t sysfs /sys /sys
mount -t tmpfs -o "nosuid,size=20%,mode=0755" tmpfs /run
mkdir -p /run/lock

# XXX devtmpfs

# Initialize dynamic linker cache.
ldconfig /usr/lib64 /usr/lib /lib64 /lib

# Fix owner of umount binary.
chown root.root /usr/bin/umount

# There is no hardware clock, just ensure the date is not miles out.
date `date -r /init +%m%d%H%M%Y`

hostname stage4-builder
echo stage4-builder.fedoraproject.org > /etc/hostname

echo
echo "This is the stage4 disk image automatic builder"
echo

# Cleanup function called on failure or exit.
cleanup ()
{
    set +e
    # Sync disks and shut down.
    sync
    sleep 5
    sync
    mount -o remount,ro / >&/dev/null
    poweroff
}
trap cleanup INT QUIT TERM EXIT ERR

set -e
set -x

rm -f /var/tmp/stage4-disk.img
rm -f /var/tmp/stage4-disk.img-t
rm -rf /var/tmp/mnt

# Create a template disk image.
truncate -s 20G /var/tmp/stage4-disk.img-t
mkfs -t ext4 /var/tmp/stage4-disk.img-t

# Create the installroot.
mkdir /var/tmp/mnt
mount -o loop /var/tmp/stage4-disk.img-t /var/tmp/mnt
mkdir /var/tmp/mnt/{dev,proc,sys}
mount -o bind /dev /var/tmp/mnt/dev
mount -o bind /proc /var/tmp/mnt/proc
mount -o bind /sys /var/tmp/mnt/sys
rpm --root /var/tmp/mnt --initdb

# For the list of core packages, see <id>core</id> in:
# https://pagure.io/fedora-comps/blob/master/f/comps-f25.xml.in
# I have added some which were needed for tdnf, or which are
# generally useful to have in the stage4.
#
# We need --releasever here because fedora-release isn't
# installed inside the chroot.
dnf --releasever 25 -y --installroot /var/tmp/mnt install \
     basesystem \
     bash \
     coreutils \
     cronie \
     curl \
     dnf \
     dnf-plugins-core \
     e2fsprogs \
     expat \
     fedora-release \
     filesystem \
     glibc \
     glib2 \
     gpgme \
     grep \
     grubby \
     hostname \
     initscripts \
     iputils \
     kbd \
     less \
     libgpg-error \
     ncurses \
     openssh-clients \
     openssh-server \
     procps-ng \
     rootfiles \
     rpm \
     setup \
     shadow-utils \
     systemd \
     tdnf \
     util-linux
# Temporarily omitted:
#    audit
# nothing provides systemd-sysv needed by audit-2.6.7-1.fc25.0.riscv64.riscv64
#    authconfig
# nothing provides policycoreutils needed by authconfig-6.2.10-14.fc25.riscv64
#    sudo
# nothing provides /usr/bin/vi needed by sudo-1.8.18-1.fc25.0.riscv64.riscv64
#    firewalld
# nothing provides python3-dbus needed by python3-firewall-0.4.3.3-1.fc25.noarch
#
# Omitted because we don't have builds for them yet:
#     dhcp-client
#     dracut-config-generic
#     dracut-config-rescue
#     initial-setup
#     iproute
#     man-db
#     NetworkManager
#     parted
#     passwd
#     plymouth
#     policycoreutils
#     selinux-policy-targeted
#     vim-minimal

# Do some configuration within the chroot.

# Disable public repos, they don't serve riscv64 packages anyway.
chroot /var/tmp/mnt \
       dnf config-manager --set-disabled updates updates-testing fedora

# Disk image is built, so move it to the final filename.
# guestfish downloads this, but if it doesn't exist, guestfish
# fails indicating the earlier error.
mv /var/tmp/stage4-disk.img-t /var/tmp/stage4-disk.img

# cleanup() is called automatically here.
