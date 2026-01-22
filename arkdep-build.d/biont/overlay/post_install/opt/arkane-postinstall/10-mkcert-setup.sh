#!/bin/bash
# First-boot mkcert CA setup
# Generates CA once and persists in /arkdep/shared/mkcert
# Subsequent deployments reuse the same CA

set -e

SHARED_MKCERT="/arkdep/shared/mkcert"
SYSTEM_MKCERT="/usr/local/share/mkcert"

# Create shared directory if needed
mkdir -p "$SHARED_MKCERT"

# Generate CA if it doesn't exist
if [ ! -f "$SHARED_MKCERT/rootCA.pem" ]; then
    echo "Generating new mkcert CA in $SHARED_MKCERT..."
    CAROOT="$SHARED_MKCERT" mkcert -install
    chmod 644 "$SHARED_MKCERT/rootCA.pem"
    # Make key readable by wheel group so ddev can generate certs
    chown root:wheel "$SHARED_MKCERT/rootCA-key.pem"
    chmod 640 "$SHARED_MKCERT/rootCA-key.pem"
fi

# Copy CA to system location
cp "$SHARED_MKCERT/rootCA.pem" "$SYSTEM_MKCERT/"
cp "$SHARED_MKCERT/rootCA-key.pem" "$SYSTEM_MKCERT/"
chmod 644 "$SYSTEM_MKCERT/rootCA.pem"
# Make key readable by wheel group so ddev can generate certs
chown root:wheel "$SYSTEM_MKCERT/rootCA-key.pem"
chmod 640 "$SYSTEM_MKCERT/rootCA-key.pem"

# Install CA to system trust store
CAROOT="$SYSTEM_MKCERT" mkcert -install

echo "mkcert CA installed from $SHARED_MKCERT"
