#! /usr/bin/env bash

AUR_PACKAGES=(ddev-bin)

declare -r aur_root="/usr/share/aur"
declare -r aur_root_abs="$workdir/$aur_root"
mkdir -p $aur_root_abs
chown -R nobody:nobody $aur_root_abs

arch-chroot $workdir bash -c "echo 'nobody ALL = (ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers"

for pkg in "${AUR_PACKAGES[@]}"; do
  
  arch-chroot $workdir sudo -u nobody bash -c "git clone https://aur.archlinux.org/$pkg.git $aur_root/$pkg"
  arch-chroot $workdir sudo -u nobody bash -c "cd $aur_root/$pkg && makepkg -si --noconfirm"
  
done

arch-chroot $workdir bash -c "sed '$d' /etc/sudoers"
rm -rf $aur_root_abs
