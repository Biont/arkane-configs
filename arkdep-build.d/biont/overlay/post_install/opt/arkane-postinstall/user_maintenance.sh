#!/usr/bin/env bash
set -euo pipefail

# Normal UID bounds (system‑wide)
UID_MIN=$(awk '/^UID_MIN/{print $2}' /etc/login.defs)
UID_MAX=$(awk '/^UID_MAX/{print $2}' /etc/login.defs)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# -----------------------------------------------------------------------
# 2️⃣  Function that adds a user to a group if they’re not already there.
# -----------------------------------------------------------------------

ensure_user_in_group() {
    local user="$1"
    local group="$2"
    echo "Ensuring user $user is added to $group..."
    # If the group does not exist yet – create it.
    if ! getent group "$group" > /dev/null; then
        echo "  → Creating missing group '$group'..."
        groupadd "$group" || {
            echo "!!! Failed to create group '$group'!"
            return 1
        }
    fi

    # Check whether the user is already a member.
    if id -nG "$user" | grep -qw "$group"; then
        echo "  • $user is already in $group – nothing to do."
    else
        echo "Ensuring /etc/group reflects /usr/lib/group..."
        grep -qE "^$group:" /etc/group || grep -E "^$group:" /usr/lib/group >> /etc/group
        echo "  → Adding $user to $group..."
        usermod -a -G "$group" "$user" || {
            echo "!!! Failed to add $user to $group!"
            return 1
        }
    fi
}

REQUIRED_GROUPS=(
wheel
docker
)


# Iterate over every user
while IFS=: read -r user _ uid _ _ homedir shell; do
  # Filter: normal UID, real home, real login shell
  if [[ $uid -ge $UID_MIN && $uid -le $UID_MAX \
      && -d "$homedir" && -x "$homedir" \
      && ! "$shell" =~ ^/(usr/sbin/nologin|bin/false)$ ]]; then

    echo ">>> Processing $user (UID=$uid, home=$homedir)"

    # 4️⃣  Ensure the user is in each required group.
    for grp in "${REQUIRED_GROUPS[@]}"; do
      ensure_user_in_group "$user" "$grp"
    done

  fi
done < <(getent passwd)

echo "Done."