#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

echo "=== engine setup start $(date) ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Scaffold quickstart project
mkdir -p /opt/iii && cd /opt/iii
iii project init quickstart --template quickstart
cd quickstart

# Add state and http workers (these run inside the engine process)
iii worker add iii-state --no-start || true
iii worker add iii-http  --no-start || true

# Create systemd service so engine survives reboots
cat > /etc/systemd/system/iii-engine.service << 'SERVICE'
[Unit]
Description=iii engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii/quickstart
ExecStart=/root/.local/bin/iii --config config.yaml
Restart=on-failure
RestartSec=5
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-engine
systemctl start  iii-engine

echo "=== engine setup done $(date) ==="
