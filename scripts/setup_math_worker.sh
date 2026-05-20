#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

ENGINE_IP="${engine_private_ip}"
echo "=== math-worker setup start $(date) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip python3-venv

mkdir -p /home/ubuntu/math-worker
cat > /home/ubuntu/math-worker/math_worker.py << 'PY'
import os
from iii import register_worker, InitOptions, Logger

iii = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="math-worker"),
)
logger = Logger()

def add_handler(payload: dict) -> dict:
    a = payload.get("a", 0)
    b = payload.get("b", 0)
    logger.info(f"math::add called in Python with a={a}, b={b}")
    result = {"c": a + b}
    running_total = iii.trigger({
        "function_id": "state::get",
        "payload": {"scope": "math", "key": "running_total"},
    })
    new_total = (running_total or 0) + result["c"]
    iii.trigger({
        "function_id": "state::set",
        "payload": {"scope": "math", "key": "running_total", "value": new_total},
    })
    result["running_total"] = new_total
    return result

iii.register_function("math::add", add_handler)
print("Math worker started - listening for calls")
PY

python3 -m venv /home/ubuntu/math-worker/.venv
/home/ubuntu/math-worker/.venv/bin/pip install iii-sdk==0.11.0 watchfiles
chown -R ubuntu:ubuntu /home/ubuntu/math-worker

cat > /etc/systemd/system/iii-math-worker.service << SERVICE
[Unit]
Description=iii math-worker (Python)
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/math-worker
ExecStart=/home/ubuntu/math-worker/.venv/bin/python math_worker.py
Restart=on-failure
RestartSec=5
Environment=III_URL=ws://$ENGINE_IP:49134

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-math-worker
systemctl start iii-math-worker
echo "=== math-worker setup done $(date) ==="
