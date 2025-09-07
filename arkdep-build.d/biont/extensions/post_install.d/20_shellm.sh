arch-chroot $workdir bash -c "wget https://raw.githubusercontent.com/Biont/shellm/refs/heads/main/shellm -o /usr/local/bin/shellm"
arch-chroot $workdir bash -c "chmod +x /usr/local/bin/shellm"