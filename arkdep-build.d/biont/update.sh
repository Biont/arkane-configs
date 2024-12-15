# Arkdep is pre EFI var drop version
if [[ -f $arkdep_boot/loader/entries/${data[0]}.conf ]]; then
	mv $arkdep_boot/loader/entries/${data[0]}.conf $arkdep_boot/loader/entries/$(date +%Y%m%d-%H%M%S)-${data[0]}+3.conf
	bootctl set-default ''
fi

if [[ -e /var/lib/fprint ]]; then
	cp -rT /var/lib/fprint $arkdep_dir/deployments/${data[0]}/rootfs/var/lib/fprint
fi

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    printf "This script must be run as root.\n" >&2
    exit 1
fi

current_swapfile="$arkdep_dir/shared/swapfile"
dracut_conf_dir="$arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf.d"
resume_conf="${dracut_conf_dir}/resume.conf"
fstab="$arkdep_dir/deployments/${data[0]}/rootfs/etc/fstab"

# Fetch total system RAM in MB
ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ram_mb=$((ram_kb / 1024))

# Unlock rootfs
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro false

swapoff "$current_swapfile"
rm "$current_swapfile"
printf "Creating BTRFS swap file of size %d MB...\n" "$ram_mb"
btrfs filesystem mkswapfile --size "${ram_mb}M" "$current_swapfile"
swapon "$current_swapfile"

# Add the swapfile to /etc/fstab
printf "Adding swapfile entry to /etc/fstab...\n"
if ! grep -qF "$current_swapfile" "$fstab"; then
    printf "%s none swap defaults 0 0\n" "$SWAPFILE" >> "$fstab"
fi

#Lock rootfs again
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro true

# Retrieve the resume offset
printf "Fetching resume offset...\n"
offset=$(btrfs inspect-internal map-swapfile -r "$current_swapfile")
if [[ -z $offset ]]; then
    printf "Failed to fetch resume offset.\n" >&2
    exit 1
fi

# Retrieve the UUID of the filesystem containing the swapfile
uuid=$(findmnt -no UUID -T "$current_swapfile")
if [[ -z $uuid ]]; then
    printf "Failed to retrieve UUID of the filesystem containing %s.\n" "$current_swapfile" >&2
    exit 1
fi

# Configure dracut with the resume information
printf "Configuring dracut with resume information...\n"
mkdir -p "$dracut_conf_dir"
printf "add_dracutcmdline=\"resume=UUID=%s resume_offset=%s\"\n" "$uuid" "$offset" > "$resume_conf"

# Rebuild dracut
printf "Rebuilding dracut configuration...\n"
dracut -q -k $arkdep_dir/deployments/${data[0]}/rootfs/usr/lib/modules/${kernels_installed[0]} \
	-c $arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf \
	--confdir $arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf.d \
	--kernel-image $arkdep_boot/arkdep/${data[0]}/vmlinuz \
	--kver ${kernels_installed[0]} \
	--force \
	$arkdep_boot/arkdep/${data[0]}/initramfs-linux.img || cleanup_and_quit 'Failed to generate initramfs'

printf "Swapfile created and configured successfully.\n"

