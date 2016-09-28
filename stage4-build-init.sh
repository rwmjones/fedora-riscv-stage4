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
rpm --root /var/tmp/mnt --initdb

# Run tdnf to install packages into the installroot.
tdnf repolist

# For the list of core packages, see <id>core</id> in:
# https://pagure.io/fedora-comps/blob/master/f/comps-f25.xml.in
# I have added some which were needed for tdnf, or which are
# generally useful to have in the stage4.
#
# We need --releasever here because fedora-release isn't
# installed inside the chroot.
tdnf --releasever 25 -y --installroot /var/tmp/mnt install \
     basesystem \
     bash \
     coreutils \
     cronie \
     curl \
     dhcp-client \
     dnf \
     dnf-plugins-core \
     dracut-config-generic \
     dracut-config-rescue \
     e2fsprogs \
     expat \
     fedora-release \
     filesystem \
     firewalld \
     glibc \
     glib2 \
     gpgme \
     grep \
     grubby \
     hostname \
     initial-setup \
     initscripts \
     iproute \
     iputils \
     kbd \
     less \
     libgpg-error \
     man-db \
     ncurses \
     NetworkManager \
     openssh-clients \
     openssh-server \
     parted \
     passwd \
     plymouth \
     policycoreutils \
     procps-ng \
     rootfiles \
     rpm \
     selinux-policy-targeted \
     setup \
     shadow-utils \
     systemd \
     tdnf \
     util-linux \
     vim-minimal
# Temporarily omitted:
#    audit
# nothing provides systemd-sysv needed by audit-2.6.7-1.fc25.0.riscv64.riscv64
#    authconfig
# nothing provides policycoreutils needed by authconfig-6.2.10-14.fc25.riscv64
#    sudo
# nothing provides /usr/bin/vi needed by sudo-1.8.18-1.fc25.0.riscv64.riscv64

# Disk image is built, so move it to the final filename.
# guestfish downloads this, but if it doesn't exist, guestfish
# fails indicating the earlier error.
mv /var/tmp/stage4-disk.img-t /var/tmp/stage4-disk.img

# cleanup() is called automatically here.
