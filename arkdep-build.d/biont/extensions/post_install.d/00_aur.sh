AUR_PACKAGES=(
waydroid
waydroid-script-git
python-pyclip
ddev-bin
aider-chat-venv
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

# Install AUR packages
arch-chroot $workdir sudo -u aurbuilder bash -c "yay -S --noconfirm ${AUR_PACKAGES[*]}"

# Install claude-desktop-native with proper setup
arch-chroot $workdir sudo -u aurbuilder bash -c "
# Ensure we're in the right directory with permissions
cd $aur_root
pwd
ls -la

# Clone the repository
git clone https://github.com/jkoelker/claude-desktop-native.git
cd claude-desktop-native

# Set npm environment to avoid permission issues
export NPM_CONFIG_CACHE=/home/aurbuilder/.npm-cache
export NPM_CONFIG_PREFIX=/home/aurbuilder/.npm-global
mkdir -p \$NPM_CONFIG_CACHE \$NPM_CONFIG_PREFIX

# Build with yay
yay -Bi . --noconfirm
"

# Cleanup
arch-chroot $workdir sudo -u aurbuilder bash -c "yay -Yc --noconfirm"
arch-chroot $workdir bash -c "
rm -f /etc/sudoers.d/aurbuilder
userdel -r aurbuilder 2>/dev/null || true
"

# Clean up the AUR directory
rm -rf $aur_root_abs