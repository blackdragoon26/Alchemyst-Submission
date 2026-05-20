#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

ENGINE_IP="${engine_private_ip}"
echo "=== caller-worker setup start $(date), engine=$ENGINE_IP ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

mkdir -p /opt/iii/caller-worker/src

cat > /opt/iii/caller-worker/package.json << 'JSON'
{
  "name": "caller-worker",
  "version": "1.0.0",
  "dependencies": {
    "@iii-dev/sdk": "latest",
    "ts-node": "^10.9.2",
    "typescript": "^5.4.5"
  }
}
JSON

cat > /opt/iii/caller-worker/src/worker.ts << 'TS'
import { Worker } from "@iii-dev/sdk";

const engineUrl = process.env.III_ENGINE_URL!;
const worker = new Worker({ engineUrl });

worker.registerFunction(
  "math::add_two_numbers",
  async (payload: { a: number; b: number }) => {
    return worker.trigger({ function_id: "math::add", payload });
  }
);

worker.registerFunction(
  "http::add_two_numbers",
  async (payload: { body: { a: number; b: number } }) => {
    const result = await worker.trigger({
      function_id: "math::add_two_numbers",
      payload: payload.body,
    });
    return {
      status_code: 200,
      body: result,
      headers: { "Content-Type": "application/json" },
    };
  }
);

worker.registerTrigger({
  type: "http",
  function_id: "http::add_two_numbers",
  config: { api_path: "/math/add-two-numbers", http_method: "POST" },
});

worker.start();
console.log("caller-worker connected to", engineUrl);
TS

cd /opt/iii/caller-worker && npm install --quiet

for i in $(seq 1 36); do
  curl -sf --max-time 3 "http://$ENGINE_IP:3111/health" && break || true
  echo "waiting for engine... ($i/36)"
  sleep 5
done

cat > /etc/systemd/system/iii-caller-worker.service << SERVICE
[Unit]
Description=iii caller-worker (TypeScript)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii/caller-worker
ExecStart=/usr/bin/npx ts-node src/worker.ts
Restart=on-failure
RestartSec=5
Environment=III_ENGINE_URL=ws://$ENGINE_IP:49134

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-caller-worker
systemctl start  iii-caller-worker

echo "=== caller-worker setup done $(date) ==="
