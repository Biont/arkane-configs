AUR_PACKAGES=(
claude-desktop
claude-code
claude-code-router
waydroid-script-git
ddev-bin
jetbrains-toolbox
jetbrains-nautilus-git
plymouth-theme-bgrt-better-luks
)

declare -r aur_root="/usr/share/aur"
declare -r aur_root_abs="$workdir/$aur_root"

# Create directory structure OUTSIDE chroot first
mkdir -p $aur_root_abs

# Create user and setup permissions INSIDE chroot
arch-chroot $workdir bash -c "
# Create build user
useradd -m -s /bin/bash aurbuilder

# Create AUR directory inside chroot and set ownership
mkdir -p $aur_root
chown -R aurbuilder:aurbuilder $aur_root

# Add sudoers permission
echo 'aurbuilder ALL = (ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers.d/aurbuilder

# Install base packages
pacman -S --needed --noconfirm git base-devel
"

# Install yay
arch-chroot $workdir sudo -u aurbuilder bash -c "
cd $aur_root
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
"

# Verify yay installation
arch-chroot $workdir sudo -u aurbuilder bash -c "which yay"

# Install AUR packages one at a time so a single broken package does not abort the batch
declare -a failed_pkgs=()
for pkg in "${AUR_PACKAGES[@]}"; do
    printf '\n=== Installing AUR package: %s ===\n' "$pkg"
    if ! arch-chroot $workdir sudo -u aurbuilder bash -c "yay -S --needed --noconfirm '$pkg'"; then
        printf '!!! AUR package failed to install: %s\n' "$pkg" >&2
        failed_pkgs+=("$pkg")
    fi
done

if (( ${#failed_pkgs[@]} > 0 )); then
    printf '\n!!! The following AUR packages were skipped due to install failures:\n' >&2
    printf '  - %s\n' "${failed_pkgs[@]}" >&2
fi

# Cleanup
arch-chroot $workdir sudo -u aurbuilder bash -c "yay -Yc --noconfirm" || true
arch-chroot $workdir bash -c "
rm -f /etc/sudoers.d/aurbuilder
userdel -r aurbuilder 2>/dev/null || true
"

# Clean up the AUR directory
rm -rf $aur_root_abs