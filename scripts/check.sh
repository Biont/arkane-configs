#!/usr/bin/env bash
# Pre-build sanity checks, cheap enough to run before every arkdep-build.
#
#  1. Vendored depends/arkanelinux-generic is pristine (matches the commit in its UPSTREAM file)
#  2. No variant overlay file shadows a dependency overlay file of the same stage.
#     Dependency overlays are copied after the variant's, so such files are silently lost.
#     Override upstream files from a later stage (post_install overlay or a post_install.d
#     script), or better, use a drop-in path upstream does not ship (e.g. sysctl.d/90-biont.conf).
#  3. Every package in the variant and its dependencies exists in the pacman.conf repos
#  4. Every AUR package in 00_aur.sh exists on the AUR
#
# Usage: scripts/check.sh [variant...]   (default: biont)
set -uo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
configsdir="$repo_root/arkdep-build.d"
variants=("${@:-biont}")
arch=x86_64

errors=0
err()  { printf '\e[1;31mERROR\e[0m %s\n' "$*"; errors=$((errors + 1)); }
warn() { printf '\e[1;33mWARN\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32mOK\e[0m    %s\n' "$*"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Strip comments and blank lines from package/depends lists
clean_list() { sed 's/#.*//;s/[[:space:]]//g;/^$/d' "$@" 2>/dev/null; }

#
# 1. Vendored upstream is pristine
#
generic="$configsdir/depends/arkanelinux-generic"
pinned=$(sed -n 's/^commit=//p' "$generic/UPSTREAM" 2>/dev/null)
if [[ -z $pinned ]]; then
	err "depends/arkanelinux-generic/UPSTREAM missing, run scripts/sync-upstream.sh"
else
	cp -a "$repo_root/scripts" "$tmp/scripts"
	mkdir -p "$tmp/arkdep-build.d/depends"
	if "$tmp/scripts/sync-upstream.sh" "$pinned" > /dev/null; then
		if diff -r "$tmp/arkdep-build.d/depends/arkanelinux-generic" "$generic" > "$tmp/pristine.diff"; then
			ok "depends/arkanelinux-generic matches upstream ${pinned:0:12}"
		else
			err "depends/arkanelinux-generic was edited by hand, move the change into the biont variant:"
			sed 's/^/        /' "$tmp/pristine.diff"
		fi
	else
		warn "could not fetch upstream ${pinned:0:12}, skipping pristine check"
	fi
fi

# Repo databases are shared between variants, cache them by URL
declare -A db_fetched
fetch_db() { # $1 = repo name, $2 = server url
	local url="${2//\$repo/$1}"
	url="${url//\$arch/$arch}/$1.db"
	local file="$tmp/db-$(printf '%s' "$url" | md5sum | cut -c1-12)"
	if [[ -z ${db_fetched[$url]:-} ]]; then
		curl -sfL -o "$file.tar" "$url" || { warn "could not fetch $url"; return 1; }
		# Names, provides and groups are all valid install targets
		tar -xOf "$file.tar" --wildcards '*/desc' | awk '
			/^%/ { section = $0; next }
			/^$/ { section = ""; next }
			section == "%NAME%" || section == "%GROUPS%" { print }
			section == "%PROVIDES%" { sub(/[<>=].*/, ""); print }
		' | sort -u > "$file"
		db_fetched[$url]=$file
	fi
	cat "${db_fetched[$url]}"
}

for variant in "${variants[@]}"; do
	variantdir="$configsdir/$variant"
	echo "--- $variant"
	[[ -d $variantdir ]] || { err "variant $variant not found"; continue; }
	mapfile -t depends < <(clean_list "$variantdir/depends.list")

	#
	# 2. Overlay shadowing
	#
	for stage in post_bootstrap post_install; do
		[[ -d $variantdir/overlay/$stage ]] || continue
		for depend in "${depends[@]}"; do
			[[ -d $configsdir/$depend/overlay/$stage ]] || continue
			while read -r f; do
				[[ -e $variantdir/overlay/$stage/$f ]] &&
					err "overlay/$stage/$f is overwritten by $depend, the variant's copy never takes effect"
			done < <(cd "$configsdir/$depend/overlay/$stage" && find . -type f -o -type l | sed 's|^\./||')
		done
	done

	#
	# 3. Repo packages exist
	#
	: > "$tmp/available"
	while read -r repo server; do
		fetch_db "$repo" "$server" >> "$tmp/available"
	done < <(awk '
		/^\[/ { gsub(/[][]/, ""); repo = $0; next }
		repo != "options" && /^Server[[:space:]]*=/ && !(repo in seen) {
			sub(/^Server[[:space:]]*=[[:space:]]*/, ""); print repo, $0; seen[repo]
		}
	' "$variantdir/pacman.conf")
	sort -u -o "$tmp/available" "$tmp/available"

	lists=("$variantdir/bootstrap.list" "$variantdir/package.list")
	for depend in "${depends[@]}"; do
		lists+=("$configsdir/$depend/bootstrap.list" "$configsdir/$depend/package.list")
	done
	missing=$(clean_list "${lists[@]}" | sort -u | comm -23 - "$tmp/available")
	if [[ -n $missing ]]; then
		err "packages not found in any pacman.conf repo: $(echo $missing)"
	else
		ok "all repo packages available"
	fi

	# Packages upstream already ships are noise in the variant lists
	dupes=$(comm -12 \
		<(clean_list "$variantdir/bootstrap.list" "$variantdir/package.list" | sort -u) \
		<(for d in "${depends[@]}"; do clean_list "$configsdir/$d/bootstrap.list" "$configsdir/$d/package.list"; done | sort -u))
	[[ -n $dupes ]] && warn "already provided by depends, can be dropped: $(echo $dupes)"

	#
	# 4. AUR packages exist
	#
	aur_script="$variantdir/extensions/post_install.d/00_aur.sh"
	[[ -f $aur_script ]] || continue
	mapfile -t aur < <(sed -n '/^AUR_PACKAGES=(/,/)/p' "$aur_script" | sed '1d;$d' | clean_list)
	(( ${#aur[@]} )) || continue
	query=$(printf '&arg[]=%s' "${aur[@]}")
	if found=$(curl -sf "https://aur.archlinux.org/rpc/v5/info?${query#&}"); then
		missing=$(comm -23 <(printf '%s\n' "${aur[@]}" | sort -u) \
			<(grep -o '"Name":"[^"]*"' <<< "$found" | cut -d'"' -f4 | sort -u))
		[[ -n $missing ]] && err "AUR packages not found: $(echo $missing)" || ok "all AUR packages available"
	else
		warn "could not reach the AUR, skipping AUR check"
	fi
done

echo
(( errors )) && { echo "$errors error(s)"; exit 1; }
echo "All checks passed"
