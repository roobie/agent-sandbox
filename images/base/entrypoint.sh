#!/bin/bash
set -e
# set -ex for debugging

# entrypoint.sh must be run as root, in order to mangle the dev user's UID and GID to match host user's.

# This script is both the container's entrypoint, but also the `dev-shell` handle
# so this script must take that into account.

# Initialize firewall if not already done
# Check if allowed-domains ipset exists (created by init-firewall.py)
if ! ipset list allowed-domains >/dev/null 2>&1; then
    echo "Initializing firewall..."
    if ! /usr/local/bin/init-firewall.py; then
        echo ""
        echo "=========================================="
        echo "FATAL: Firewall initialization failed!"
        echo "Container cannot start without working firewall."
        echo "Check the errors above and rebuild the image."
        echo "=========================================="
        exit 1
  fi
else
  echo "Firewall already initialized."
fi

cd /workspace

# the host bind mount is
TARGET_DIR=.

# Get UID/GID of the mounted directory on the host (as seen in container)
HOST_UID=$(stat -c '%u' "$TARGET_DIR")
HOST_GID=$(stat -c '%g' "$TARGET_DIR")

# Existing app user (created in Dockerfile)
APP_USER=dev
APP_GROUP=dev

# Adjust group if necessary
if [ "$HOST_GID" != "0" ] && [ "$HOST_GID" != "$(id -g "$APP_USER")" ]; then
    # If a group with HOST_GID exists, reuse it; otherwise, modify app's group
    if getent group "$HOST_GID" >/dev/null 2>&1; then
        APP_GROUP=$(getent group "$HOST_GID" | cut -d: -f1)
    else
        groupmod -g "$HOST_GID" "$APP_GROUP"
    fi
fi

# Adjust user UID
if [ "$HOST_UID" != "0" ] && [ "$HOST_UID" != "$(id -u "$APP_USER")" ]; then
    usermod -u "$HOST_UID" -g "$HOST_GID" "$APP_USER"
fi

# by this point, the dev user should be able to write to /workspace

HOME_DIR="/home/$APP_USER"

# Fix ownership of internal (non-bind-mount) dirs that this user needs.
# and then chown'ing the whole HOME
chown -R "$APP_USER":"$APP_GROUP" "$HOME_DIR"
chown -R "$APP_USER":"$APP_GROUP" "/commandhistory"

# Drop privileges
exec gosu "$APP_USER" "${@:-zsh}"
