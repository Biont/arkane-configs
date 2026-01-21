# Arkdep is pre EFI var drop version
if [[ -f $arkdep_boot/loader/entries/${data[0]}.conf ]]; then
	mv $arkdep_boot/loader/entries/${data[0]}.conf $arkdep_boot/loader/entries/$(date +%Y%m%d-%H%M%S)-${data[0]}+3.conf
	bootctl set-default ''
fi

if [[ -e /var/lib/fprint ]]; then
	cp -rT /var/lib/fprint $arkdep_dir/deployments/${data[0]}/rootfs/var/lib/fprint
fi

# Migrate Docker data to persistent location
# This ensures Docker images and volumes survive image deployments
if [[ -d /var/lib/docker ]] && [[ ! -d $arkdep_dir/shared/docker ]]; then
	printf "Migrating Docker data to persistent location...\n"
	mkdir -p $arkdep_dir/shared/docker
	# Stop Docker if running
	systemctl stop docker.socket docker.service 2>/dev/null || true
	# Copy existing Docker data to persistent location
	if [[ -n "$(ls -A /var/lib/docker 2>/dev/null)" ]]; then
		cp -a /var/lib/docker/* $arkdep_dir/shared/docker/
		printf "Docker data migrated successfully.\n"
	fi
fi

# Ensure Docker shared directory exists
mkdir -p $arkdep_dir/shared/docker

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
printf "add_dracutmodules+=\" resume \"\n" > "$resume_conf"
printf "add_dracutcmdline=\"resume=UUID=%s resume_offset=%s\"\n" "$uuid" "$offset" >> "$resume_conf"

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

echo "Setting up users and groups."

REQUIRED_GROUPS=(
wheel
docker
)


# Iterate over every login user with a home
while IFS=: read -r user _ uid _ _ homedir shell; do
  # Filter: normal UID, real home, real login shell
  if [[ $uid -ge $UID_MIN && $uid -le $UID_MAX \
      && -d "$homedir" && -x "$homedir" \
      && ! "$shell" =~ ^/(usr/sbin/nologin|bin/false)$ ]]; then

    echo ">>> Processing $user (UID=$uid, home=$homedir)"

    # 4️⃣  Ensure the user is in each required group.
    for grp in "${REQUIRED_GROUPS[@]}"; do
      echo ">>> Adding $user to group $grp"
      chroot /arkdep/deployments/${data[0]}/rootfs usermod -aG "$grp" "$user"
    done

  fi
done < <(getent passwd)

echo "Done setting up users/groups."

