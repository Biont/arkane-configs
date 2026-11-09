
# Arkdep is pre EFI var drop version
if [[ -f $arkdep_boot/loader/entries/${data[0]}.conf ]]; then
	mv $arkdep_boot/loader/entries/${data[0]}.conf $arkdep_boot/loader/entries/$(date +%Y%m%d-%H%M%S)-${data[0]}+3.conf
	bootctl set-default ''
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

# Only (re)create the swapfile when it is missing or smaller than RAM.
# Recreating it on every deploy is risky: swapoff can fail under memory pressure,
# and the physical offset changes, invalidating resume info of other deployments.
swap_bytes=$(stat -c %s "$current_swapfile" 2>/dev/null || echo 0)
if (( swap_bytes < ram_mb * 1024 * 1024 )); then
    recreate_swap=1
    if swapon --show=NAME --noheadings | grep -qxF "$current_swapfile"; then
        if ! swapoff "$current_swapfile"; then
            printf "Failed to disable %s, keeping existing swapfile.\n" "$current_swapfile" >&2
            recreate_swap=0
        fi
    fi
    if [[ $recreate_swap -eq 1 ]]; then
        rm -f "$current_swapfile"
        printf "Creating BTRFS swap file of size %d MB...\n" "$ram_mb"
        btrfs filesystem mkswapfile --size "${ram_mb}M" "$current_swapfile" ||
            cleanup_and_quit 'Failed to create swapfile'
        swapon "$current_swapfile"
    fi
else
    printf "Existing swapfile is large enough, keeping it.\n"
fi

# Retrieve the resume offset
printf "Fetching resume offset...\n"
offset=$(btrfs inspect-internal map-swapfile -r "$current_swapfile")
if [[ -z $offset ]]; then
    cleanup_and_quit 'Failed to fetch resume offset'
fi

# Retrieve the UUID of the filesystem containing the swapfile
uuid=$(findmnt -no UUID -T "$current_swapfile")
if [[ -z $uuid ]]; then
    cleanup_and_quit "Failed to retrieve UUID of the filesystem containing $current_swapfile"
fi

# Unlock rootfs
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro false

# Migrate enrolled fingerprint data from the running deployment.
# Must run after the rootfs is unlocked above, otherwise the copy fails silently.
if [[ -e /var/lib/fprint ]]; then
    cp -rT /var/lib/fprint $arkdep_dir/deployments/${data[0]}/rootfs/var/lib/fprint
fi

# Add the swapfile to /etc/fstab
if ! grep -qE "^${current_swapfile}[[:space:]]" "$fstab"; then
    printf "Adding swapfile entry to /etc/fstab...\n"
    printf "%s none swap defaults 0 0\n" "$current_swapfile" >> "$fstab"
fi

# Back a /var path with a shared Btrfs subvolume so it survives deployments.
# On first creation the subvolume is seeded from the running system, so data
# that so far lived in the per-deployment /var is carried over once.
root_device=$(findmnt -no SOURCE -T "$arkdep_dir" | sed 's/\[.*\]//')
persist_shared() {
    local name=$1 path=$2
    local subvol="$arkdep_dir/shared/$name"
    if [[ ! -d "$subvol" ]]; then
        printf "Creating shared Btrfs subvolume for %s...\n" "$path"
        btrfs subvolume create "$subvol"
        if [[ -d "$path" ]] && ! mountpoint -q "$path"; then
            printf "Seeding %s from the running deployment...\n" "$subvol"
            cp -a --reflink=auto "$path/." "$subvol/"
        fi
    fi
    mkdir -p "$arkdep_dir/deployments/${data[0]}/rootfs$path"
    # Drop any existing (possibly duplicated) entries, then add exactly one
    sed -i "\\#subvol=arkdep/shared/$name\\([,[:space:]]\\|\$\\)#d" "$fstab"
    printf "%s %s btrfs subvol=arkdep/shared/%s 0 0\n" "$root_device" "$path" "$name" >> "$fstab"
}

persist_shared waydroid /var/lib/waydroid
# Docker volumes (ddev databases) and containers live in /var/lib/docker, images
# in /var/lib/containerd (containerd snapshotter). Both must persist together.
persist_shared docker /var/lib/docker
persist_shared containerd /var/lib/containerd

# Ensure tpm2-device=auto is set in crypttab entries for TPM2 auto-unlock
crypttab="$arkdep_dir/deployments/${data[0]}/rootfs/etc/crypttab"
if [[ -f "$crypttab" ]] && ! grep -q 'tpm2-device=auto' "$crypttab"; then
    printf "Adding tpm2-device=auto to crypttab entries...\n"
    sed -i -r '/^[[:space:]]*(#|$)/!{
        s/^(([^[:space:]]+[[:space:]]+){3})([^[:space:]]+)[[:space:]]*$/\1\3,tpm2-device=auto/
        t
        s/[[:space:]]*$/\ttpm2-device=auto/
    }' "$crypttab"
fi

# Make sure the resume module is included in the initramfs. The resume location itself
# goes on the kernel command line below, systemd-hibernate-resume only reads /proc/cmdline.
mkdir -p "$dracut_conf_dir"
printf "add_dracutmodules+=\" resume \"\n" > "$resume_conf"

# Point dracut to the deployment's firmware for ACPI table override
acpi_fw_dir="$arkdep_dir/deployments/${data[0]}/rootfs/lib/firmware/acpi"
if [[ -d "$acpi_fw_dir" ]]; then
    printf 'acpi_table_dir="%s"\n' "$acpi_fw_dir" > "${dracut_conf_dir}/acpi-table-dir.conf"
fi

#Lock rootfs again
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro true

printf "Adding kernel parameters to bootloader entry...\n"
boot_entries=($arkdep_boot/loader/entries/*${data[0]}*.conf)
if [[ ! -f ${boot_entries[0]} ]]; then
    cleanup_and_quit 'Failed to find bootloader entry for kernel parameters'
fi

# dracut only embeds kernel_cmdline in the initramfs, where the kernel itself never
# sees it. Collect it from the deployment's dracut config (including /arkdep/overlay
# additions) and put anything not yet present on the real kernel command line.
dracut_cmdline=$(
    kernel_cmdline=
    for f in $arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf "$dracut_conf_dir"/*.conf; do
        [[ -f $f ]] && . "$f"
    done
    printf '%s' "$kernel_cmdline"
)
entry_options=" $(grep -h '^options ' "${boot_entries[@]}") "
extra_params=
for param in $dracut_cmdline; do
    [[ $entry_options == *" $param "* || $extra_params == *" $param"* ]] || extra_params+=" $param"
done
extra_params=$(printf '%s' "$extra_params" | sed 's/[&|\\]/\\&/g')

# Resume information goes on the command line as well, so resume does not depend
# solely on the HibernateLocation EFI variable written by systemd-sleep
sed -i -E "/^options /{s| resume(_offset)?=[^ ]*||g; s|\$|${extra_params} resume=UUID=${uuid} resume_offset=${offset}|}" \
    "${boot_entries[@]}"

# Rebuild dracut
printf "Rebuilding dracut configuration...\n"
dracut -q -k $arkdep_dir/deployments/${data[0]}/rootfs/usr/lib/modules/${kernels_installed[0]} \
	-c $arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf \
	--confdir $arkdep_dir/deployments/${data[0]}/rootfs/etc/dracut.conf.d \
	--kernel-image $arkdep_boot/arkdep/${data[0]}/vmlinuz \
	--kver ${kernels_installed[0]} \
	--force \
	$arkdep_boot/arkdep/${data[0]}/initramfs-linux.img || cleanup_and_quit 'Failed to generate initramfs'

printf "Swapfile and resume configured successfully.\n"

echo "Setting up users and groups."

REQUIRED_GROUPS=(
wheel
docker
)


# Regular user UID range, as used by useradd
login_defs="$arkdep_dir/deployments/${data[0]}/rootfs/etc/login.defs"
UID_MIN=$(awk '$1 == "UID_MIN" {print $2}' "$login_defs")
UID_MAX=$(awk '$1 == "UID_MAX" {print $2}' "$login_defs")
UID_MIN=${UID_MIN:-1000}
UID_MAX=${UID_MAX:-60000}

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
