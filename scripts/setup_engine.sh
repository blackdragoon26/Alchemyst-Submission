#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

echo "=== engine setup start $(date) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git jq

curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/home/ubuntu/.local/bin:$PATH"

cp /home/ubuntu/.local/bin/iii        /usr/local/bin/iii
cp /home/ubuntu/.local/bin/iii-worker /usr/local/bin/iii-worker

mkdir -p /opt/iii
chown ubuntu:ubuntu /opt/iii
cd /opt/iii
sudo -u ubuntu iii project init quickstart --template quickstart
cd /opt/iii/quickstart

cat > /opt/iii/quickstart/config.yaml << 'YAML'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0
  - name: iii-queue
    config:
      adapter:
        name: builtin
  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: ./data/state_store.db
  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
YAML

cat > /etc/systemd/system/iii-engine.service << 'SERVICE'
[Unit]
Description=iii engine
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/iii/quickstart
ExecStart=/usr/local/bin/iii --config config.yaml
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine
echo "=== engine setup done $(date) ==="
