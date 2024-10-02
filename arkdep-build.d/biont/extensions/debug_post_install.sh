#! /usr/bin/env bash
declare -r build_image='/var/tmp/arkdep-build.img'
declare -r build_image_mountpoint='/var/tmp/arkdep-build'
declare -r workdir="$build_image_mountpoint/rootfs"
declare -r build_image_size='15G'
# Minimum required storage in KiB
declare -r minimum_available_root_storage='31457280' # 30G
declare -r minimum_available_var_storage='20971520' # 20G

# Cleanup and quit if error
cleanup_and_quit () {

	# If any paramters are passed we will assume it to be an error
	[[ -n $1 ]] && printf "\e[1;31m<#>\e[0m $*\e[0m\n" >&2

	if [[ $ARKDEP_NO_CLEANUP -eq 1 ]]; then
		printf 'Cleanup disabled, not running cleanup\n'
		exit 1
	fi

	umount -Rl $build_image_mountpoint

	rm $build_image
	rm -rf $build_image_mountpoint

	# Quit program if argument provided to function
	if [[ -n $1 ]]; then
		exit 1
	fi

	# Otherwise just quit, there is no error
	exit 0

}
printf '\e[1;34m-->\e[0m\e[1m Creating disk image\e[0m\n'
fallocate -l $build_image_size $build_image || cleanup_and_quit "Failed to create disk image at $build_image"
mkfs.btrfs -f $build_image || cleanup_and_quit "Failed to partition $build_image"
printf "\e[1;34m-->\e[0m\e[1m Mounting $build_image at $workdir\e[0m\n"
# The data is compressed to minimize writes to the disk, the actual export does not maintain this compression
mount -m -t btrfs -o loop,compress=zstd $build_image $build_image_mountpoint || cleanup_and_quit "Failed to mount disk image to $workdir"

# Create temporary Btrfs subvolume
printf "\e[1;34m-->\e[0m\e[1m Creating temporary Btrfs subvolumes at $workdir\e[0m\n"
btrfs subvolume create $workdir/ || cleanup_and_quit "Failed to create btrfs subvolume $workdir)"
mount --bind $workdir $workdir || cleanup_and_exit "Failed to bind mount disk $workdir"
btrfs subvolume create $workdir/etc || cleanup_and_quit "Failed to create btrfs subvolume $workdir/etc)"
btrfs subvolume create $workdir/var || cleanup_and_quit "Failed to create btrfs subvolume $workdir/var)"


source post_install.sh


