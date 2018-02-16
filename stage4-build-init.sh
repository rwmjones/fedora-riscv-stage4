#!/bin/bash -
# Init used to build the stage4.

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
mknod /dev/loop0 b 7 0
mknod /dev/loop1 b 7 1
mknod /dev/loop2 b 7 2
rm -f /dev/null
mknod /dev/null c 1 3
rm -f /dev/ptmx
mknod /dev/ptmx c 5 2
rm -f /dev/tty /dev/zero
mknod /dev/tty c 5 0
mknod /dev/zero c 1 5
rm -f /dev/vd{a,b}
mknod /dev/vda b 254 0
mknod /dev/vdb b 254 16
rm -f /dev/random /dev/urandom
mknod /dev/random c 1 8
mknod /dev/urandom c 1 9

# Initialize dynamic linker cache.
ldconfig /usr/lib64 /usr/lib /lib64 /lib

# There is no hardware clock, just ensure the date is not miles out.
date `date -r /init +%m%d%H%M%Y`
openrdate 0.fedora.pool.ntp.org

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

# Allow telnet to work.
if test -x /usr/sbin/xinetd && test -x /usr/sbin/in.telnetd ; then
    cat > /etc/xinetd.d/telnet <<EOF
service telnet
{
        flags           = REUSE
        socket_type     = stream
        wait            = no
        user            = root
        server          = /usr/sbin/in.telnetd
       server_args     = -L /etc/login
        log_on_failure  += USERID
}
EOF
    cat > /etc/login <<EOF
#!/bin/bash -
exec bash -i -l
EOF
    chmod +x /etc/login
    xinetd -stayalive -filelog /var/log/xinetd.log
fi

hostname stage4-builder
echo stage4-builder.fedoraproject.org > /etc/hostname

echo
echo "This is the stage4 disk image automatic builder"
echo

# Clean the dnf cache.
dnf clean all

# Cleanup function called on failure or exit.
cleanup ()
{
    set +e
    # Sync disks and shut down.
    sync
    sleep 5
    sync
    mount.static -o remount,ro / >&/dev/null
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
mount -o rbind /dev /var/tmp/mnt/dev
mount -o rbind /proc /var/tmp/mnt/proc
mount -o rbind /sys /var/tmp/mnt/sys
rpm --root /var/tmp/mnt --initdb

# Adding glibc-langpack-en avoids the huge glibc-all-langpacks
# being used.
#
# We need --releasever here because fedora-release isn't
# installed inside the chroot.
#
# strict=0 is like the old --skip-broken option in yum.  We can
# remove it when all @core packages are available.
# [Uncomment this when we have dnf]
#dnf -y --releasever=25 --installroot=/var/tmp/mnt --setopt=strict=0 \
#     install \
#         @core \
#         glibc-langpack-en
rm -f /etc/yum.repos.d/*.repo
cp /var/tmp/local.repo /etc/yum.repos.d
tdnf="tdnf --releasever f27 --installroot /var/tmp/mnt"
$tdnf repolist
$tdnf clean all
$tdnf makecache
# This was the core list of f25, plus some extras.
$tdnf -y install \
      glibc-langpack-en \
      audit \
      basesystem \
      bash \
      coreutils \
      cronie \
      curl \
      e2fsprogs \
      filesystem \
      firewalld \
      glibc \
      hostname \
      iproute \
      kbd \
      less \
      ncurses \
      openrdate \
      parted \
      passwd \
      procps-ng \
      rootfiles \
      rpm \
      setup \
      shadow-utils \
      sudo \
      util-linux \
      vim-minimal \
      \
      e2fsprogs \
      tdnf \
      \
      fpc-srpm-macros \
      ghc-srpm-macros \
      gnat-srpm-macros \
      go-srpm-macros \
      nim-srpm-macros \
      ocaml-srpm-macros \
      openblas-srpm-macros \
      perl-generators \
      perl-srpm-macros \
      python-srpm-macros \
      \
      hack-gcc \
      cpio \
      diffutils \
      elfutils \
      findutils \
      gawk \
      glibc-headers \
      grep \
      gzip \
      info \
      make \
      patch \
      redhat-rpm-config \
      rpm-build \
      sed \
      tar \
      unzip \
      which \
      xz
#      NetworkManager
#      authconfig
#      dhcp-client
#      dnf
#      dnf-plugins-core
#      iputils
#      man-db
#      openssh-clients
#      openssh-server
#      plymouth
#      policycoreutils
#      selinux-policy-targeted
#      systemd

# Do some configuration within the chroot.

# Write an fstab for the chroot.
cat > /var/tmp/mnt/etc/fstab <<EOF
/dev/root / ext4 defaults 0 0
EOF

# Set the hostname.
echo stage4.fedoraproject.org > /var/tmp/mnt/etc/hostname

# Copy local.repo in.
cp /var/tmp/local.repo /var/tmp/mnt/etc/yum.repos.d

# Set up /init (in the chroot) as a symlink.
# [Uncomment this when we have systemd]
#pushd /var/tmp/mnt
#ln -s usr/lib/systemd/systemd init
#popd
# [Temporarily ...]
cp /var/tmp/init.sh /var/tmp/mnt/init
chmod 0555 /var/tmp/mnt/init

# Add the root-shell systemd service.
#cp /var/tmp/root-shell.service /var/tmp/mnt/etc/systemd/system/
#chroot /var/tmp/mnt \
#       systemctl enable root-shell

# Copy in the poweroff command.
# [Remove this when we have systemd]
cp /var/tmp/poweroff /var/tmp/mnt/usr/sbin/poweroff
chmod 0555 /var/tmp/mnt/usr/sbin/poweroff

# Disable public repos, they don't serve riscv64 packages anyway.
# [Uncomment this when we have dnf]
#chroot /var/tmp/mnt \
#       dnf config-manager --set-disabled updates updates-testing fedora
# [instead ...]
for f in /var/tmp/mnt/etc/yum.repos.d/fedora*.repo; do
    mv $f $f.disabled
done

# Clean DNF cache in the chroot.  This forces the first run of DNF
# by the new machine to refresh the cache and not use the stale
# data from the build environment.
# [Uncomment this when we have dnf]
#chroot /var/tmp/mnt \
#       dnf clean all

# List all the packages which were installed in the chroot
# so they appear in the build.log.
chroot /var/tmp/mnt rpm -qa | sort

# Unmount the chroot.  Unfortunately some processes are still running
# in the chroot, so we can't do that.
sync

# Disk image is built, so move it to the final filename.
# guestfish downloads this, but if it doesn't exist, guestfish
# fails indicating the earlier error.
mv /var/tmp/stage4-disk.img-t /var/tmp/stage4-disk.img

# cleanup() is called automatically here.
