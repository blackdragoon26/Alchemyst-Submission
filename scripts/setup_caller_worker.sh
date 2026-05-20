#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

ENGINE_IP="${engine_private_ip}"
echo "=== caller-worker setup start $(date) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

mkdir -p /home/ubuntu/caller-worker/src

cat > /home/ubuntu/caller-worker/package.json << 'JSON'
{
  "name": "caller-worker",
  "version": "0.1.0",
  "type": "module",
  "dependencies": { "iii-sdk": "0.11.0" },
  "devDependencies": {
    "@types/node": "^25.2.2",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
JSON

cat > /home/ubuntu/caller-worker/src/worker.ts << 'TS'
import { registerWorker, Logger } from 'iii-sdk';

const iii = registerWorker(process.env.III_URL ?? 'ws://localhost:49134');
const logger = new Logger();

iii.registerFunction(
  'math::add_two_numbers',
  async (payload: { a: number; b: number }) => {
    logger.info('math::add_two_numbers called in TypeScript', payload);
    const result = await iii.trigger({ function_id: 'math::add', payload });
    return result;
  },
);

iii.registerFunction(
  'http::add_two_numbers',
  async (payload: { body: { a: number; b: number } }) => {
    const result = await iii.trigger({
      function_id: 'math::add_two_numbers',
      payload: payload.body,
    });
    return {
      status_code: 200,
      body: { c: result.c, running_total: result.running_total },
      headers: { 'Content-Type': 'application/json' },
    };
  },
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::add_two_numbers',
  config: { api_path: '/math/add-two-numbers', http_method: 'POST' },
});

console.log('Caller worker started');
TS

cd /home/ubuntu/caller-worker && npm install
chown -R ubuntu:ubuntu /home/ubuntu/caller-worker

cat > /etc/systemd/system/iii-caller-worker.service << SERVICE
[Unit]
Description=iii caller-worker (TypeScript)
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/caller-worker
ExecStart=/usr/bin/node --import tsx/esm src/worker.ts
Restart=on-failure
RestartSec=5
Environment=III_URL=ws://$ENGINE_IP:49134
Environment=NODE_NO_WARNINGS=1

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iii-caller-worker
systemctl start iii-caller-worker
echo "=== caller-worker setup done $(date) ==="
