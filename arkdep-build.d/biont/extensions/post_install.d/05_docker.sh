arch-chroot $workdir systemctl enable --now docker.socket
arch-chroot $workdir chmod 666 /var/run/docker.sock
arch-chroot $workdir systemctl enable systemd-gig@11434.socket
arch-chroot $workdir systemctl enable systemd-gig@7860.socket

# Symlink Docker data to persistent shared storage
rm -rf $workdir/var/lib/docker
ln -s /arkdep/shared/docker $workdir/var/lib/docker

