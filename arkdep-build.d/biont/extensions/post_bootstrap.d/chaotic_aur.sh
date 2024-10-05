
# Add keys for Chaotic AUR
# https://aur.chaotic.cx/docs
arch-chroot $workdir pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
arch-chroot $workdir pacman-key --lsign-key 3056513887B78AEB
arch-chroot $workdir pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm
arch-chroot $workdir pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm

CONTENT="

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
"
arch-chroot $workdir echo "$CONTENT" >> /etc/pacman.conf

arch-chroot $workdir pacman -Syu --noconfirm
