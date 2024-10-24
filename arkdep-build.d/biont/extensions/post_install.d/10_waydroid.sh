echo "Setting up Waydroid"
arch-chroot $workdir waydroid init -s GAPPS
arch-chroot $workdir systemctl enable waydroid-container.service
arch-chroot $workdir waydroid prop set persist.waydroid.multi_windows true
arch-chroot $workdir -a 13 install libndk
arch-chroot $workdir -a 13 install widevine
