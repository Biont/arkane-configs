AUR_PACKAGES=(
waydroid
waydroid-script-git
python-pyclip
ddev-bin
aider-chat-venv
jetbrains-toolbox
plymouth-theme-bgrt-better-luks
)

declare -r aur_root="/usr/share/aur"
declare -r aur_root_abs="$workdir/$aur_root"
mkdir -p $aur_root_abs
chown -R nobody:nobody $aur_root_abs

arch-chroot $workdir bash -c "echo 'nobody ALL = (ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers.d/nobody"
arch-chroot $workdir bash -c "usermod --expiredate= nobody"
arch-chroot $workdir bash -c "pacman -S --needed --noconfirm git base-devel"
arch-chroot $workdir sudo -u nobody bash -c "cd $aur_root && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm"
arch-chroot $workdir sudo -u nobody bash -c "yay -S --noconfirm ${AUR_PACKAGES[*]}"
arch-chroot $workdir sudo -u nobody bash -c "yay -Yc --noconfirm"

arch-chroot $workdir bash -c "rm /etc/sudoers.d/nobody"
rm -rf $aur_root_abs
