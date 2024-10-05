echo "Setting up swap"

OFFSET=$(arch-chroot $workdir btrfs inspect-internal map-swapfile -r /arkdep/shared/swapfile)

DRACUT="
add_dracutmodules+=\" resume \"
kernel_cmdline+=\" resume=/dev/disk/by-label/arkane_root resume_offset=$OFFSET \"
"

#arch-chroot $workdir echo $DRACUT > /etc/dracut.conf.d/resume-from-hibernate.conf

arch-chroot $workdir systemctl enable resize-swap.service
