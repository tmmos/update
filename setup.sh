#!/bin/bash
set -euo pipefail

# Check the number of arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <PORT> <USERNAME> <PASSWORD> <SSH_USERNAME> <SSH_PASSWORD>"
    exit 1
fi

# Assign arguments to variables
PORT="$1"                # Port on which pproxy will run
PROXY_USERNAME="$2"      # Proxy username
PROXY_PASSWORD="$3"      # Proxy password
SSH_USERNAME="$4"        # SSH username (the user running the script, must have sudo privileges)
SSH_PASSWORD="$5"        # Password for SSH_USERNAME

# Verify that PORT is a number and within the valid range (1024-65535)
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "PORT must be a number." >&2
    exit 1
fi

if (( PORT < 1024 || PORT > 65535 )); then
    echo "PORT must be between 1024 and 65535." >&2
    exit 1
fi

# If not running as root, automatically switch to root using sudo
if [[ $EUID -ne 0 ]]; then
    echo "Not running as root. Switching to root..."
    # Use sudo -S and automatically provide the password
    echo "$SSH_PASSWORD" | sudo -S "$0" "$@"
    exit $?
fi

echo "Running as root."

# Check for the existence of pip3
if command -v pip3 >/dev/null 2>&1; then
    echo "pip3 is installed at: $(command -v pip3)"
else
    echo "pip3 not found. Please install pip3 on the system." >&2
    exit 1
fi

# Check and install/upgrade pproxy
if command -v pproxy >/dev/null 2>&1; then
    PPROXY_PATH=$(command -v pproxy)
    echo "pproxy is installed at: $PPROXY_PATH"
else
    echo "Installing/upgrading system-wide pproxy..."
    if ! pip3 install --upgrade pproxy; then
        echo "Failed to install/upgrade pproxy." >&2
        exit 1
    fi
    if command -v pproxy >/dev/null 2>&1; then
        PPROXY_PATH=$(command -v pproxy)
        echo "pproxy is installed at: $PPROXY_PATH"
    else
        echo "pproxy installation failed; executable not found." >&2
        exit 1
    fi
fi

# Check for systemctl (systemd)
if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found. This script requires systemd support." >&2
    exit 1
fi

# Since running as root, the service file will be placed in /etc/systemd/system
SERVICE_FILE="/etc/systemd/system/muser.service"

echo "Creating/updating service file: $SERVICE_FILE"
mkdir -p "$(dirname "$SERVICE_FILE")"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PPROXY Proxy Service
After=network.target

[Service]
ExecStart=$PPROXY_PATH -l "socks5+http://0.0.0.0:$PORT#$PROXY_USERNAME:$PROXY_PASSWORD"
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

echo "Reloading systemd daemon..."
if ! systemctl daemon-reload; then
    echo "Failed to reload systemd configuration." >&2
    exit 1
fi

echo "Enabling muser.service..."
if ! systemctl enable muser.service; then
    echo "Failed to enable muser.service." >&2
    exit 1
fi

if systemctl is-active --quiet muser.service; then
    echo "Restarting muser.service..."
    if ! systemctl restart muser.service; then
        echo "Failed to restart muser.service." >&2
        exit 1
    fi
else
    echo "Starting muser.service..."
    if ! systemctl start muser.service; then
        echo "Failed to start muser.service." >&2
        exit 1
    fi
fi

if systemctl is-active --quiet muser.service; then
    echo "muser.service is running successfully."
else
    echo "muser.service failed to run." >&2
    exit 1
fi

echo "Clearing logs and history for security..."
rm -f ~/.bash_history ~/.python_history ~/.wget-hsts || true
history -c 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

echo "pproxy is running on port $PORT with authentication $PROXY_USERNAME:$PROXY_PASSWORD."
