#!/bin/bash
# Workspace ONE MDM enrollment
#
# Reads enrollment credentials from /arkdep/shared/workspace-one.conf.
# Skips enrollment silently if the file is not present.
#
# Expected config file format:
#   WS1_SERVER="https://your-server.awmdm.com"
#   WS1_USER="username"
#   WS1_PASSWORD="password"
#   WS1_GROUP="groupid"

set -e

declare -r ws1_conf="/arkdep/shared/workspace-one.conf"

if [ ! -f "$ws1_conf" ]; then
    echo "Workspace ONE: $ws1_conf not found, skipping enrollment."
    exit 0
fi

source "$ws1_conf"

if [ -z "$WS1_SERVER" ] || [ -z "$WS1_USER" ] || [ -z "$WS1_PASSWORD" ] || [ -z "$WS1_GROUP" ]; then
    echo "Workspace ONE: incomplete configuration in $ws1_conf, skipping enrollment."
    exit 0
fi

echo "Workspace ONE: enrolling with server $WS1_SERVER..."
ws1HubUtil enroll \
    --server "$WS1_SERVER" \
    --user "$WS1_USER" \
    --password "$WS1_PASSWORD" \
    --group "$WS1_GROUP"

echo "Workspace ONE: enrollment complete."
