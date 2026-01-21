arch-chroot $workdir systemctl enable arkane-postinstall.service
arch-chroot $workdir systemctl enable dnsmasq.service

# Enable a plymouth theme that is better at dealing with the LUKS password prompt
# Installed by ßß_aur.sh
arch-chroot $workdir plymouth-set-default-theme bgrt-better-luks

# taken from here: https://forum.endeavouros.com/t/polished-single-user-booting-or-heavy-lifting-with-plymouth/54464/4
# I have yet to figure out if it does anything
arch-chroot $workdir systemctl mask plymouth-quit.service

# Set up mkcert system-wide CA for DDEV SSL
# Create system-wide CAROOT directory
mkdir -p $workdir/usr/local/share/mkcert
chmod 755 $workdir/usr/local/share/mkcert

# Generate CA and install to system trust store
arch-chroot $workdir bash -c "
export CAROOT=/usr/local/share/mkcert
mkcert -install
"

# Ensure CA files are readable
chmod 644 $workdir/usr/local/share/mkcert/*

# Make mkcert user setup script executable
chmod +x $workdir/usr/local/bin/setup-mkcert-user