# Build the stage4 disk image.
# By Richard W.M. Jones <rjones@redhat.com>
# See README.

#----------------------------------------------------------------------
# Configuration.

# If riscv-autobuild is running in another directory and creating
# RPMs, then point to them here:
rpmsdir    = /mnt/dev/fedora-riscv-autobuild/RPMS
# otherwise download https://fedorapeople.org/groups/risc-v/RPMS/
# using recursive wget and point to your local copy of it here:
#rpmsdir   = RPMS

# Kernel, get this from https://fedorapeople.org/groups/risc-v/disk-images/
vmlinux    = vmlinux

# Existing stage4 is needed to build a new one.  Get a working stage4
# from https://fedorapeople.org/groups/risc-v/disk-images/ and rename
# it to this name:
old_stage4 = old-stage4-disk.img

# End of configuration.
#----------------------------------------------------------------------

all: stage4-disk.img.xz stage4-full-fat-disk.img.xz

stage4-disk.img.xz: stage4-disk.img
	rm -f $@
	xz --best -k $^
	ls -lh $@

stage4-disk.img: stage4-builder.img stage4-temporary-init.sh poweroff local.repo
	rm -f $@ $@-t build.log
	$(MAKE) boot-in-qemu DISK=stage4-builder.img |& tee build.log
# Copy out the new stage4.
	virt-cat -a stage4-builder.img /var/tmp/stage4-disk.img > $@-t
# Upload the fixed files into the image.
	guestfish -a $@-t -i \
	    upload stage4-temporary-init.sh /init : \
	    chmod 0755 /init : \
	    upload poweroff /usr/bin/poweroff : \
	    chmod 0755 /usr/bin/poweroff : \
	    upload local.repo /etc/yum.repos.d/local.repo : \
	    chmod 0644 /etc/yum.repos.d/local.repo
# Sparsify it.
	virt-sparsify --inplace $@-t
	mv $@-t $@

# This is the modified stage4 which builds a new stage4.
stage4-builder.img: $(old_stage4) stage4-build-init.sh
	rm -f $@ $@-t
	cp $< $@-t
	guestfish -a $@-t -i \
	    upload stage4-build-init.sh /init : \
	    chmod 0755 /init : \
	    copy-in $(rpmsdir) /var/tmp : \
	    upload local.repo /etc/yum.repos.d/local.repo : \
	    chmod 0644 /etc/yum.repos.d/local.repo
	mv $@-t $@

# Poweroff program.
poweroff: poweroff.c
	/usr/bin/riscv64-unknown-linux-gnu-gcc --sysroot=/usr/sysroot $^ -o $@

# The "full-fat" variant contains all the RPMs at time of building.
# This is just for convenience.  Once we get networking fixed, we
# should stop building this.
stage4-full-fat-disk.img.xz: stage4-full-fat-disk.img
	rm -f $@
	xz --best -k $^
	ls -lh $@

stage4-full-fat-disk.img: stage4-disk.img
	rm -f $@ $@-t
	cp $< $@-t
	guestfish -a $@-t -i \
		copy-in $(rpmsdir) /var/tmp
	mv $@-t $@

# Boot $(DISK) in qemu.
boot-in-qemu: $(DISK) $(vmlinux)
	qemu-system-riscv -m 4G -kernel /usr/bin/bbl \
	    -append $(vmlinux) \
	    -drive file=$(DISK),format=raw -nographic

# Boot new stage4 in qemu (useful for testing).
boot-stage4-in-qemu: stage4-disk.img
	$(MAKE) boot-in-qemu DISK=$<

boot-stage4-full-fat-in-qemu: stage4-full-fat-disk.img
	$(MAKE) boot-in-qemu DISK=$<

# Upload the new stage4 disk image.
upload-stage4: stage4-disk.img.xz stage4-full-fat-disk.img.xz $(vmlinux)
	scp $^ fedorapeople.org:/project/risc-v/disk-images/
	scp upload-readme fedorapeople.org:/project/risc-v/disk-images/readme.txt
	scp build.log fedorapeople.org:/project/risc-v/disk-images/

clean:
	rm -f poweroff
	rm -f stage4-builder.img
	rm -f *-t
	rm -f *~

distclean: clean
	rm -f stage4-disk.img
	rm -f stage4-disk.img.xz
	rm -f $(vmlinux)
	rm -f $(old_stage4)
