#!/bin/bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "This script should not be run as root." >&2
    exit 1
fi

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <PORT> <USERNAME> <PASSWORD>"
    exit 1
fi

PORT="$1"
USERNAME="$2"
PASSWORD="$3"

if command -v pip3 >/dev/null 2>&1; then
    echo "pip3 is already installed at: $(command -v pip3)"
else
    echo "pip3 not found. Installing locally..."
    mkdir -p "$HOME/.local/bin"
    wget https://bootstrap.pypa.io/get-pip.py -O "$HOME/get-pip.py"
    python3 "$HOME/get-pip.py" --user
    rm -f "$HOME/get-pip.py"
fi

export PATH="$HOME/.local/bin:$PATH"

if command -v pproxy >/dev/null 2>&1; then
    PPROXY_PATH=$(command -v pproxy)
    echo "pproxy is already installed at: $PPROXY_PATH"
else
    echo "Installing/upgrading pproxy..."
    pip3 install --user --upgrade pproxy || { echo "Failed to install/upgrade pproxy." >&2; exit 1; }
    if command -v pproxy >/dev/null 2>&1; then
        PPROXY_PATH=$(command -v pproxy)
        echo "pproxy is installed at: $PPROXY_PATH"
    else
        if [ -f "$HOME/.local/bin/pproxy" ]; then
            PPROXY_PATH="$HOME/.local/bin/pproxy"
        elif [ -f "/usr/local/bin/pproxy" ]; then
            PPROXY_PATH="/usr/local/bin/pproxy"
        else
            echo "pproxy installation failed; executable not found." >&2
            exit 1
        fi
        echo "pproxy is installed at: $PPROXY_PATH"
    fi
fi

SERVICE_FILE="$HOME/.config/systemd/user/muser.service"
echo "Creating/updating service file: $SERVICE_FILE"
mkdir -p "$HOME/.config/systemd/user"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PPROXY Proxy Service
After=network.target

[Service]
ExecStart=$PPROXY_PATH -l "socks5+http://0.0.0.0:$PORT#$USERNAME:$PASSWORD"
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

echo "Reloading systemd configuration..."
systemctl --user daemon-reload || { echo "Failed to reload systemd configuration." >&2; exit 1; }

echo "Enabling pproxy service to start on boot..."
systemctl --user enable muser.service || { echo "Failed to enable muser.service." >&2; exit 1; }

if systemctl --user is-active --quiet muser.service; then
    echo "Restarting pproxy service..."
    systemctl --user restart muser.service || { echo "Failed to restart muser.service." >&2; exit 1; }
else
    echo "Starting pproxy service..."
    systemctl --user start muser.service || { echo "Failed to start muser.service." >&2; exit 1; }
fi

echo "Clearing logs and history for security..."
rm -f ~/.bash_history ~/.python_history ~/.wget-hsts
history -c 2>/dev/null
journalctl --user --rotate >/dev/null 2>&1
journalctl --user --vacuum-time=1s >/dev/null 2>&1

echo "pproxy is running on port $PORT with authentication $USERNAME:$PASSWORD."
