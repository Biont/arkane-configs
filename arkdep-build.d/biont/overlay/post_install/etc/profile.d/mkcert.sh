# Use system-wide mkcert CA for DDEV certificates
export CAROOT=/usr/local/share/mkcert

# Set up mkcert CA for browsers (installs to NSS database for Chromium)
if [ -x /usr/bin/setup-mkcert-user ]; then
    /usr/bin/setup-mkcert-user
fi
