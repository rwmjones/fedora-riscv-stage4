#!/bin/bash -
# Temporary init used until we have systemd.

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
mkdir -p /dev/pts
mount -t devpts /dev/pts /dev/pts
mkdir -p /dev/shm
mount -t tmpfs -o mode=1777 shmfs /dev/shm

# XXX devtmpfs
#mount -t devtmpfs /dev /dev

rm -f /dev/loop*
mknod /dev/loop-control c 10 237
chown root.disk /dev/loop-control
chmod 0660 /dev/loop-control
mknod /dev/loop0 b 7 0
mknod /dev/loop1 b 7 1
mknod /dev/loop2 b 7 2
rm -f /dev/null
mknod /dev/null c 1 3
chmod 0666 /dev/null
rm -f /dev/ptmx
mknod /dev/ptmx c 5 2
chown root.tty /dev/ptmx
chmod 0666 /dev/ptmx
rm -f /dev/tty /dev/zero
mknod /dev/tty c 5 0
chown root.tty /dev/tty
chmod 0666 /dev/tty
mknod /dev/zero c 1 5
chown root.root /dev/zero
chmod 0666 /dev/zero
rm -f /dev/vd{a,b}
mknod /dev/vda b 254 0
mknod /dev/vdb b 254 16
rm -f /dev/random /dev/urandom
mknod /dev/random c 1 8
mknod /dev/urandom c 1 9
chmod 0666 /dev/random /dev/urandom

# Initialize dynamic linker cache.
ldconfig /usr/lib64 /usr/lib /lib64 /lib

# There is no hardware clock, just ensure the date is not miles out.
date `date -r /init +%m%d%H%M%Y`

# Bring up the network.
# (Note: These commands won't work unless the iproute package has been
# installed in a previous boot)
if ip -V >&/dev/null; then
    ip a add 10.0.2.15/255.255.255.0 dev eth0
    ip link set eth0 up
    ip r add default via 10.0.2.2 dev eth0
    ip a list
    ip r list
fi

echo 'nameserver 8.8.4.4' > /etc/resolv.conf

# Try to set the time from a time server.
rdate 0.fedora.pool.ntp.org &

# Generate SSH host keys if not done already.
/usr/bin/ssh-keygen -A

# Start SSH server.
/usr/sbin/sshd

hostname stage4
echo stage4.fedoraproject.org > /etc/hostname

echo
echo "Welcome to the Fedora/RISC-V stage4 disk image"
echo "https://fedoraproject.org/wiki/Architectures/RISC-V"
echo

PS1='stage4:\w\$ '
export PS1

# Run bash.
bash -il

# Sync disks and shut down.
sync
mount.static -o remount,ro / >&/dev/null
poweroff
