arch-chroot $workdir systemctl enable arkane-postinstall.service
arch-chroot $workdir systemctl enable dnsmasq.service
arch-chroot $workdir systemctl enable caddy.service

# Enable a plymouth theme that is better at dealing with the LUKS password prompt
# Installed by ßß_aur.sh
arch-chroot $workdir plymouth-set-default-theme bgrt-better-luks

# taken from here: https://forum.endeavouros.com/t/polished-single-user-booting-or-heavy-lifting-with-plymouth/54464/4
# I have yet to figure out if it does anything
arch-chroot $workdir systemctl mask plymouth-quit.service

# Set up mkcert directory (CA generated on first boot via arkane-postinstall)
mkdir -p $workdir/usr/local/share/mkcert
chmod 755 $workdir/usr/local/share/mkcert

# Make mkcert user setup script executable
chmod +x $workdir/usr/bin/setup-mkcert-user