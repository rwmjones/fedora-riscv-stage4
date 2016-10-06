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

# Kernel.
#
# Either download this from:
#   https://fedorapeople.org/groups/risc-v/disk-images/
# or build it from:
#   https://github.com/rwmjones/fedora-riscv-kernel
vmlinux    = vmlinux

# Existing stage4 is needed to build a new one.  Get a working stage4
# from https://fedorapeople.org/groups/risc-v/disk-images/ and rename
# it to this name:
old_stage4 = old-stage4-disk.img

# End of configuration.
#----------------------------------------------------------------------

all: stage4-disk.img.xz
#stage4-full-fat-disk.img.xz

stage4-disk.img.xz: stage4-disk.img
	rm -f $@
	xz --best -k $^
	ls -lh $@

stage4-disk.img: stage4-builder.img local.repo
	rm -f $@ $@-t build.log
	$(MAKE) boot-in-qemu DISK=stage4-builder.img |& tee build.log
# Copy out the new stage4.
	virt-cat -a stage4-builder.img /var/tmp/stage4-disk.img > $@-t
# Upload the fixed files into the image.
	guestfish -a $@-t -i \
	    ln-sf /usr/lib/systemd/systemd /init : \
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
	    rm-f /init : \
	    upload stage4-build-init.sh /init : \
	    chmod 0755 /init : \
	    copy-in $(rpmsdir) /var/tmp : \
	    upload local.repo /etc/yum.repos.d/local.repo : \
	    chmod 0644 /etc/yum.repos.d/local.repo
	mv $@-t $@

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

# Boot new stage4 in qemu (for testing, does not alter the original).
boot-stage4-in-qemu: stage4-disk.img
	cp $< $<.test
	$(MAKE) boot-in-qemu DISK=$<.test
	rm $<.test

boot-stage4-full-fat-in-qemu: stage4-full-fat-disk.img
	cp $< $<.test
	$(MAKE) boot-in-qemu DISK=$<.test
	rm $<.test

# Upload the new stage4 disk image.
upload-stage4: stage4-disk.img.xz
#stage4-full-fat-disk.img.xz
	scp $^ fedorapeople.org:/project/risc-v/disk-images/
	scp upload-readme fedorapeople.org:/project/risc-v/disk-images/readme.txt
	scp build.log fedorapeople.org:/project/risc-v/disk-images/

clean:
	rm -f stage4-builder.img
	rm -f *-t
	rm -f *~

distclean: clean
	rm -f stage4-disk.img
	rm -f stage4-disk.img.xz
	rm -f $(vmlinux)
	rm -f $(old_stage4)
