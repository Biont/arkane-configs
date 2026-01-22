# Arkane Linux Custom Image Maintenance Guide

## Overview

This repository contains configuration for a custom **Arkane Linux** image built with **arkdep-build**. Arkane Linux is an immutable, atomic, Arch-based distribution using the arkdep toolkit for system management.

**Key Concepts:**
- **Immutable**: Root filesystem is read-only by default
- **Atomic**: Updates apply completely or not at all
- **Image-based**: System deployed as complete filesystem images
- **Btrfs**: Uses Btrfs subvolumes for efficient storage

## Repository Structure

```
arkdep-build.d/
├── biont/                      # Main custom variant
│   ├── type                    # Distribution type (archlinux)
│   ├── bootstrap.list          # Minimal packages for initial bootstrap
│   ├── package.list            # Full package list for installation
│   ├── depends.list            # Dependency on other variants
│   ├── pacman.conf             # Pacman configuration with repos
│   ├── name.sh                 # Script generating image name
│   ├── update.sh               # Post-deployment configuration script
│   ├── extensions/             # Build hooks directory
│   │   ├── pre_build.sh        # (optional) Runs after Btrfs subvolumes created
│   │   ├── post_bootstrap.sh   # Runs after base system bootstrap
│   │   ├── post_bootstrap.d/   # Scripts run by post_bootstrap.sh
│   │   ├── post_install.sh     # Runs after package installation
│   │   ├── post_install.d/     # Scripts run by post_install.sh
│   │   └── post_build.sh       # (optional) Runs after final image export
│   └── overlay/                # File overlays
│       ├── post_bootstrap/     # Files copied after bootstrap
│       └── post_install/       # Files copied after package install
└── minimal/                    # Minimal variant (depends on biont)
```

## Build Process Flow

### Stage 1: Initialization
1. Create Btrfs virtual disk image
2. Create subvolumes for build
3. Execute `pre_build.sh` if present

### Stage 2: Bootstrap
1. Install minimal packages from `bootstrap.list` using pacstrap
2. Execute `post_bootstrap.sh` hook
3. Copy files from `overlay/post_bootstrap/` to rootfs

### Stage 3: Package Installation
1. Install packages from `package.list`
2. Copy files from `overlay/post_install/` to rootfs
3. Copy files from dependency `overlay/post_install/` (can overwrite variant files!)
4. Execute `post_install.sh` hook

### Stage 4: Finalization
1. **Move directories to /var and create symlinks:**
   - `/usr/local` → `/var/usrlocal` (symlink: `/usr/local` → `../var/usrlocal`)
   - `/opt` → `/var/opt` (symlink: `/opt` → `var/opt`)
   - `/srv` → `/var/srv`
   - `/mnt` → `/var/mnt`
2. Create mountpoints for shared subvolumes (`/root`, `/arkdep`, `/var/lib/flatpak`)
3. Generate initramfs
4. Create bootloader entries
5. Execute `post_build.sh` if present
6. Export as `.tar.zst` archive

**Important:** The symlink creation in Stage 4 means overlay files placed in `/opt/` end up in `/var/opt/` at runtime.

## Build Environment Variables

Available in extension scripts:

| Variable | Description |
|----------|-------------|
| `$build_image` | Location of virtual Btrfs disk |
| `$build_image_mountpoint` | Mountpoint of build image filesystem |
| `$build_image_size` | Size of build image |
| `$workdir` | Root filesystem location (`$build_image_mountpoint/rootfs`) |
| `$variant` | Name of variant being built |
| `$variantdir` | Location of variant directory |

## Extension Scripts

### Hook Execution Pattern

Both `post_bootstrap.sh` and `post_install.sh` follow this pattern:
```bash
for f in $SCRIPT_DIR/post_*.d/*.sh; do
  execute_script "$f"
done
```

Scripts in `.d/` directories execute in alphanumeric order (00_, 05_, 10_, 20_, etc.).

### Current Extension Scripts

**post_bootstrap.d/**
- `00_example.sh` - Example/placeholder script

**post_install.d/**
- `00_aur.sh` - Install AUR packages using temporary build user
- `05_docker.sh` - Enable Docker socket and systemd-gig services
- `10_postinstall.sh` - Enable services, configure Plymouth, install mkcert
- `20_shellm.sh` - Download and install shellm utility

### Working with chroot

Use `arch-chroot $workdir` to execute commands inside the build environment:
```bash
arch-chroot $workdir systemctl enable service-name
arch-chroot $workdir pacman -S package-name
```

## Package Management

### Package Lists

**bootstrap.list**: Minimal packages for bootable system
- Microcodes (amd-ucode, intel-ucode)
- Essential services (dbus-broker-units)

**package.list**: Full system packages organized by category
- GNOME desktop environment
- Hardware support (printing, scanning)
- Development tools (Docker, DDEV)
- AI tools (ROCm, hipblas)
- Custom Arkane packages

### Adding Packages

**From official repos:**
1. Add package name to `arkdep-build.d/biont/package.list`
2. Rebuild image

**From AUR:**
1. Add package name to `AUR_PACKAGES` array in `arkdep-build.d/biont/extensions/post_install.d/00_aur.sh`
2. Rebuild image

### Repository Configuration

`pacman.conf` defines package sources:
```
[arkane]              # Arkane Linux packages
[arkane-cauldron]     # Arkane development packages
[core]                # Arch core
[extra]               # Arch extra
[multilib]            # 32-bit support
```

## Overlay System

Files in overlay directories copy directly to rootfs, preserving directory structure.

### Overlay Copy Order (Important!)

During build, overlays are copied in this order:
1. Variant's `overlay/post_install/` files are copied first
2. Dependency overlays (from `depends.list`) are copied **after** and can **overwrite** variant files

This means if a base dependency (like `arkanelinux-generic`) has the same file path, it will overwrite your variant's version. To avoid conflicts, use unique file paths or place files in locations the base doesn't use.

### Overlay vs Migrated Files

**Critical:** Some directories are **migrated between deployments**, meaning files from the previous deployment are copied to the new one. These migrated files can overwrite overlay files:

**Migrated paths (defined in arkdep config):**
- `var/usrlocal` (which is `/usr/local` via symlink)
- `var/opt` (which is `/opt` via symlink)
- `var/srv`, `var/lib/AccountsService`, `var/lib/bluetooth`
- `var/lib/NetworkManager`, `var/lib/arkane`, `var/db`
- `etc/localtime`, `etc/locale.gen`, `etc/locale.conf`
- `etc/NetworkManager/system-connections`, `etc/ssh`
- `etc/fstab`, `etc/crypttab`, `etc/luks-keys`
- `etc/passwd`, `etc/shadow`, `etc/group`, `etc/subuid`, `etc/subgid`

**Consequence:** If you place a script in `overlay/post_install/usr/local/bin/`, it may be overwritten by a migrated version from a previous deployment. **Prefer `/usr/bin/` for custom scripts** to avoid this issue.

### Post-Bootstrap Overlay

**Purpose**: System configuration that must exist before package installation

**Examples:**
- `/etc/hostname` - System hostname
- `/etc/dracut.conf.d/` - Initramfs configuration
- `/etc/systemd/` - Systemd configuration
- `/etc/dconf/` - GNOME settings
- `/etc/sudoers.d/` - Sudo configuration
- `/usr/abin/` - Immutability helper scripts

### Post-Install Overlay

**Purpose**: Configuration for installed packages and services

**Examples:**
- `/etc/systemd/system/` - Service units (systemd-gig, arkane-postinstall)
- `/etc/skel/` - Default user configs (.zshrc, .profile)
- `/usr/bin/` - User executables
- `/opt/llm/docker/` - LLM service configurations (Ollama, Open WebUI, MCPO)

## Key Subsystems

### systemd-gig

Socket-activated Docker container manager for LLM services.

**Components:**
- `systemd-gig@.socket` - Listens on port (%i)
- `systemd-gig@.service` - Proxies to container port
- `systemd-gig-proxy@.service` - Starts/manages container
- `/usr/bin/systemd-gig` - Helper script

**Configuration:** `/etc/systemd-containers/gig/%i.conf`
```bash
WORKING_DIRECTORY=/var/opt/llm/docker
TARGET_PORT=7860
TIMEOUT=60s
EXEC_START=docker compose up
EXEC_STOP=docker compose down
```

**Active Services:**
- Port 11434: Ollama
- Port 7860: Open WebUI

### arkane-postinstall

One-time setup scripts run at first boot.

**Mechanism:**
1. `arkane-postinstall.service` runs at boot
2. Executes all `.sh` files in `/var/opt/arkane-postinstall/`
3. Deletes each script after successful execution
4. Aborts on first failure

**Use Case:** User-specific configuration that requires running system

### Variant Dependencies

`depends.list` references base configurations:
```
depends/arkanelinux-generic
```

This pulls packages and overlays from the base Arkane Linux variant, allowing customization without duplicating base configuration.

## Building Images

### Local Build

**Manual build:**
```bash
sudo arkdep-build biont
sudo mv target/biont-*.tar.zst /arkdep/cache/
sudo arkdep deploy cache biont
```

**Using apply.sh:**
```bash
./apply.sh biont
```

### CI/CD Build

GitHub Actions workflow (`.github/workflows/arkdep-build.yml`):
- Trigger: `workflow_dispatch` (manual)
- Matrix: `EDITION: [biont]`
- Action: `.github/actions/arkdep-action`

**Build artifacts:**
- `biont-YYYY-MM-DD-XXXXXXXXXX.tar.zst` - Deployable image
- `biont-YYYY-MM-DD-XXXXXXXXXX.pkgs` - Package manifest

## update.sh - Post-Deployment Hook

Runs after deploying new image, before reboot. Has access to:
- `$arkdep_dir` - `/arkdep`
- `$arkdep_boot` - Boot partition
- `${data[0]}` - Deployment ID

**Current update.sh tasks:**
1. Migrate EFI boot entries (pre-v3 compatibility)
2. Copy fingerprint data from previous deployment
3. Create/configure BTRFS swapfile for hibernation
4. Configure dracut resume parameters
5. Rebuild initramfs with resume support
6. Add users to required groups (wheel, docker)

**Critical sections:**
```bash
# Unlock rootfs for modifications
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro false

# ... make changes ...

# Lock rootfs again
btrfs property set -f -ts $arkdep_dir/deployments/${data[0]}/rootfs ro true
```

## Safety Guidelines

### Read-Only Filesystem

System is immutable by default. Modifications require:
1. **Build new image**: Proper method for permanent changes
2. **Overlay mounts**: Temporary changes (advanced)
3. **update.sh**: Post-deployment configuration only

### Writable Locations

**Persistent across deployments (Btrfs subvolumes mounted via fstab):**
- `/home/` - User data (mounted from `arkdep/shared/home` subvolume)
- `/root/` - Root user home (mounted from `arkdep/shared/root` subvolume)
- `/var/lib/flatpak/` - Flatpak apps (mounted from `arkdep/shared/flatpak` subvolume)
- `/arkdep/` - Arkdep data directory (mounted from `arkdep` subvolume)
- `/arkdep/shared/` - Parent directory for shared subvolumes, useful for custom persistent data

**Symlinked to /var (contents migrated between deployments):**
- `/usr/local/` → `/var/usrlocal/` - Local programs and scripts
- `/opt/` → `/var/opt/` - Optional/add-on packages
- `/srv/` → `/var/srv/` - Site-specific data
- `/mnt/` → `/var/mnt/` - Mount points

**Writable but reset on each deployment:**
- Most of `/var/` - Variable data, logs (except mounted/symlinked paths)
- `/etc/` - Local configuration (arkdep overlay system, some files migrated)

### Shared Subvolume Structure

```
/arkdep/
├── shared/
│   ├── home/          # → mounted at /home
│   ├── root/          # → mounted at /root
│   ├── flatpak/       # → mounted at /var/lib/flatpak
│   ├── swapfile       # Swap file for hibernation
│   └── mkcert/        # (example) Custom persistent data
├── deployments/       # All deployed images
│   └── biont-2026-01-22-xxxxx/
│       └── rootfs/    # The actual root filesystem
├── cache/             # Downloaded images before deployment
├── overlay/           # User overlay (copied to / on demand)
└── tracker            # Tracks deployment order
```

**Use `/arkdep/shared/` for data that must persist across deployments** but doesn't fit in `/home`. Example: system-wide CA certificates, shared configuration.

### Package Management

**DO NOT** run `pacman -S` on deployed system. Packages install to image, but changes lost on reboot.

**Correct workflow:**
1. Add package to `package.list` or AUR script
2. Rebuild image
3. Deploy new image

### System Updates

**DO NOT** run `pacman -Syu` on deployed system.

**Correct workflow:**
1. Pull latest package versions (update package lists if needed)
2. Rebuild image with current packages
3. Deploy new image
4. Rollback available if issues occur

### Testing Changes

**Before committing:**
1. Build image locally
2. Deploy to test system/VM
3. Verify functionality
4. Commit configuration changes

**Rollback:** Previous deployments remain available in bootloader.

## Common Operations

### Add GNOME Extension
```bash
# Add to package.list
echo "gnome-shell-extension-name" >> arkdep-build.d/biont/package.list
# Rebuild
./apply.sh biont
```

### Add System Service
1. Create service file in `overlay/post_install/etc/systemd/system/`
2. Enable in extension script:
```bash
arch-chroot $workdir systemctl enable service-name
```

### Modify GNOME Defaults
Edit files in `overlay/post_bootstrap/etc/dconf/db/gnome.d/`

### Add User Script
Place in `overlay/post_install/usr/bin/`. **Avoid `/usr/local/bin/`** as it gets symlinked to `/var/usrlocal/bin/` which is migrated between deployments and can overwrite your overlay files.

### Add Docker Compose Service
1. Place compose file in `overlay/post_install/opt/service-name/`
2. Create systemd-gig config
3. Enable socket in extension script

### Modify Kernel Parameters
Edit `overlay/post_bootstrap/etc/dracut.conf.d/biont.conf`

### Add First-Boot Script
Place script in `overlay/post_install/opt/arkane-postinstall/`. During build, `/opt` is moved to `/var/opt` and symlinked, so your script ends up at `/var/opt/arkane-postinstall/` where `arkane-postinstall.service` expects it.

**Do NOT place in `overlay/post_install/var/opt/`** - this will cause the build to fail because arkdep-build tries to move `/opt` to `/var/opt` which would then be non-empty.

## Troubleshooting

### Build Fails at Bootstrap
- Check `bootstrap.list` package names
- Verify `pacman.conf` repository URLs
- Ensure GPG keys configured

### Build Fails at Package Install
- Check `package.list` for typos
- Verify packages exist in configured repos
- Check AUR package names in `00_aur.sh`

### Extension Script Fails
- Scripts execute in alphanumeric order
- Check dependencies between scripts
- Use `arch-chroot $workdir` for in-image commands
- Verify paths use `$workdir` prefix

### Deployed System Won't Boot
- Check dracut configuration
- Verify kernel installed
- Review bootloader entries in `/arkdep/boot/loader/entries/`
- Boot previous deployment from bootloader menu

### Changes Don't Persist
- Verify changes made in build process, not on deployed system
- Check file placed in correct overlay directory
- Ensure not modifying read-only paths on deployed system

### Overlay Files Being Overwritten
If your overlay file keeps getting replaced with an old version:
1. **Check migrated paths**: Files in `/usr/local/` (`var/usrlocal`), `/opt/` (`var/opt`), and other migrated paths are copied from previous deployments
2. **Solution**: Move the file to a non-migrated location like `/usr/bin/` instead of `/usr/local/bin/`
3. **Check dependency overlays**: Base variants (in `depends.list`) copy their overlays AFTER yours and can overwrite

### Build Fails: "unable to remove target: Directory not empty"
This happens when placing files directly in `/var/opt/` in the overlay. The build tries to move `/opt` to `/var/opt` but finds it non-empty.
- **Solution**: Place files in `overlay/post_install/opt/` instead of `overlay/post_install/var/opt/`

## Reference Commands

```bash
# Build image
sudo arkdep-build biont

# List available images
sudo arkdep list

# Deploy from cache
sudo arkdep deploy cache biont

# Deploy from file
sudo arkdep deploy file /path/to/image.tar.zst

# Check current deployment
arkdep status

# View deployment history
ls -la /arkdep/deployments/

# Check boot entries
ls -la /arkdep/boot/loader/entries/

# View build logs during build
journalctl -f

# Test changes in chroot (after build starts)
sudo arch-chroot /tmp/arkdep-build.*/rootfs
```

## Architecture Notes

### Image Naming

Generated by `name.sh`:
```bash
echo "biont-$(date +%Y-%m-%d)-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)"
```
Format: `biont-YYYY-MM-DD-RANDOM10CHARS`

### Multi-Variant Strategy

- **biont**: Full-featured desktop with development tools
- **minimal**: Lightweight variant inheriting biont base via symlinks
  - `extensions -> ../biont/extensions`
  - `overlay -> ../biont/overlay`
  - Empty `package.list` (only base from depends)

Use minimal for testing base configuration without full package set.

## Arkdep Runtime Configuration

The deployed system uses `/arkdep/config` for runtime behavior. Key settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `deploy_keep` | 3 | Number of deployments to keep |
| `enable_overlay` | 1 | Enable `/arkdep/overlay` system |
| `migrate_files` | (see below) | Paths migrated between deployments |

**Default migrated files:**
```
var/usrlocal var/opt var/srv var/lib/AccountsService var/lib/bluetooth
var/lib/NetworkManager var/lib/arkane var/lib/power-profiles-daemon var/db
etc/localtime etc/locale.gen etc/locale.conf etc/NetworkManager/system-connections
etc/ssh etc/fstab etc/crypttab etc/luks-keys etc/passwd etc/shadow etc/group
etc/subuid etc/subgid
```

## Additional Resources

- [Arkane Linux Documentation](https://docs.arkanelinux.org/)
- [arkdep-build Usage](https://docs.arkanelinux.org/arkdep/arkdep-build-usage/)
- [Arkane Linux GitHub](https://github.com/arkanelinux/)
- [This Repository](https://github.com/Biont/arkane-configs/)
