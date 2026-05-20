#!/bin/bash
set -euo pipefail
exec > /var/log/iii-setup.log 2>&1

ENGINE_IP="${engine_private_ip}"
echo "=== gateway setup start $(date), engine=$ENGINE_IP ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx curl

cat > /etc/nginx/sites-available/iii << NGINX
server {
    listen 80;
    server_name _;

    location /healthz {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass         http://$ENGINE_IP:3111\;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 120s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/iii /etc/nginx/sites-enabled/iii
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "=== gateway setup done $(date) ==="
