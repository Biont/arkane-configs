export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock

# Set up mkcert CA for browsers (runs once per user)
if [ -x /usr/local/bin/setup-mkcert-user ]; then
    /usr/local/bin/setup-mkcert-user
fi
