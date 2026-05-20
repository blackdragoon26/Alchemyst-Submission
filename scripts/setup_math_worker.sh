#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

ENGINE_IP="${engine_private_ip}"
echo "=== math-worker setup start $(date), engine=$ENGINE_IP ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git python3 python3-pip python3-venv

# Install iii CLI (needed for its Python SDK)
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Write worker source code
mkdir -p /opt/iii/math-worker
cat > /opt/iii/math-worker/worker.py << 'PY'
import os, logging
from iii import Worker

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

engine_url = os.environ["III_ENGINE_URL"]
worker = Worker(engine_url=engine_url)

@worker.function("math::add")
def add_handler(payload: dict) -> dict:
    a = payload.get("a", 0)
    b = payload.get("b", 0)
    logger.info(f"math::add  a={a} b={b}")
    result = {"c": a + b}

    running_total = worker.trigger({
        "function_id": "state::get",
        "payload": {"scope": "math", "key": "running_total"},
    })
    new_total = (running_total or 0) + result["c"]
    worker.trigger({
        "function_id": "state::set",
        "payload": {"scope": "math", "key": "running_total", "value": new_total},
    })
    result["running_total"] = new_total
    return result

worker.start()
PY

# Python venv + SDK
python3 -m venv /opt/iii/math-worker/.venv
/opt/iii/math-worker/.venv/bin/pip install --quiet iii-sdk

# Wait up to 3 min for engine to be ready
for i in $(seq 1 36); do
  curl -sf --max-time 3 "http://$ENGINE_IP:3111/health" && break || true
  echo "waiting for engine... ($i/36)"
  sleep 5
done

cat > /etc/systemd/system/iii-math-worker.service << SERVICE
[Unit]
Description=iii math-worker (Python)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii/math-worker
ExecStart=/opt/iii/math-worker/.venv/bin/python worker.py
Restart=on-failure
RestartSec=5
Environment=III_ENGINE_URL=ws://$ENGINE_IP:49134

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-math-worker
systemctl start  iii-math-worker

echo "=== math-worker setup done $(date) ==="
