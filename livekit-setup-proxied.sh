#!/bin/bash

## Use this script if the server livekit is installed
## 1. Does not have a public ip
## 2. Another server reverse proxies the request to livekit
## 3. DNS is mapped to the reverse proxy server and not livekit server

## Nginx or Reverse Proxy Configuration that needs to be used:
# sudo apt-get install libnginx-mod-stream -y (stream for nginx)
# Add this to the bottom of /etc/nginx/nginx.conf
# stream {
#     map $ssl_preread_server_name $backend_name {
#         livekit.domain.com    livekit_private;
#         default               local_http;
#     }

#     upstream livekit_private {
#         server 10.x.x.x:443; # Replace with your LiveKit Private IP
#     }

#     upstream local_http {
#         server 127.0.0.1:444; # The "Secret" port for your existing sites
#     }

#     server {
#         listen 443;
#         proxy_pass $backend_name;
#         ssl_preread on;
#     }

#     Direct UDP Forwarding (No SNI possible for UDP)
#     server {
#         listen 7882 udp;
#         proxy_pass 10.x.x.x:7882; # Replace with your LiveKit Private IP
#         proxy_timeout 10m;
#         proxy_responses 0;
#     }

#     server {
#         listen 3478 udp;
#         proxy_pass 10.x.x.x:3478; # Replace with your LiveKit Private IP
#     }

#     server {
#         listen 7881;
#         proxy_pass $backend_name;
#         ssl_preread on;
#     }
# }

# ==============================================================================
# Configuration Variables
# ==============================================================================
LIVEKIT_DOMAIN="livekit.domain.com"
LIVEKIT_IP="X.X.X.X"
LIVEKIT_CONFIG_DIR="/opt/livekit"
LIVEKIT_CERTS_DIR="/opt/livekit/certs"
LIVEKIT_CERT_FILE="domain.crt"
LIVEKIT_KEY_FILE="domain.key"
API_KEY="APIkbSL89cHqVXY"
API_SECRET="LNFIALFMmdkUTFRFCvp88BAvifFFF3toPg6I1f41ctK"

# ==============================================================================
# Execution - Optimized for Fresh Ubuntu
# ==============================================================================

echo "Starting LiveKit setup for ${LIVEKIT_DOMAIN} on fresh Ubuntu..."

# 1. System Updates & Basic Dependencies
sudo apt-get update && sudo apt-get install -y curl sed grep

# 2. CLEANUP: Ensure no directory/file conflicts
sudo rm -rf "${LIVEKIT_CONFIG_DIR}/caddy.yaml" "${LIVEKIT_CONFIG_DIR}/livekit.yaml"
sudo mkdir -p "${LIVEKIT_CONFIG_DIR}/caddy_data" "${LIVEKIT_CERTS_DIR}"

# 3. SSL Placeholders (match nginx paths)
sudo mkdir -p /home/user/livekit/certs
sudo cp -r "${LIVEKIT_CERTS_DIR}"/* /home/user/livekit/certs/ 2>/dev/null || true
sudo touch "${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
sudo touch "${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"
sudo chmod 755 "${LIVEKIT_CERTS_DIR}"
sudo chmod 644 "${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
sudo chmod 644 "${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"

# 4. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
fi
sudo systemctl enable --now docker

# 5. Install NGINX
echo "Installing NGINX..."
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# 6. NGINX Config (matches your working config)
echo "Writing NGINX configuration..."
sudo tee /etc/nginx/sites-available/${LIVEKIT_DOMAIN} > /dev/null << EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name ${LIVEKIT_DOMAIN};

    # Your certificates
    ssl_certificate ${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE};
    ssl_certificate_key ${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    # WebSocket proxy to LiveKit signaling
    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

# Enable site + disable default
sudo ln -sf /etc/nginx/sites-available/${LIVEKIT_DOMAIN} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# 7. LiveKit Config
echo "Writing LiveKit configuration..."
sudo tee "${LIVEKIT_CONFIG_DIR}/livekit.yaml" > /dev/null << EOF
port: 7880
bind_addresses:
    - "127.0.0.1"
rtc:
    tcp_port: 7881
    udp_port: 7882
    use_external_ip: false
    node_ip: ${LIVEKIT_IP}
redis:
    address: localhost:6379
    db: 0
    use_tls: false
turn:
    enabled: true
    domain: ${LIVEKIT_DOMAIN}
    tls_port: 5349
    udp_port: 3478
    external_tls: true
keys:
    ${API_KEY}: ${API_SECRET}
EOF

# 8. Docker Compose file
echo "Writing Docker Compose file..."
sudo tee "${LIVEKIT_CONFIG_DIR}/docker-compose.yaml" > /dev/null << EOF
services:
  livekit:
    image: livekit/livekit-server:latest
    command: --config /etc/livekit.yaml
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml:ro
  redis:
    image: redis:7-alpine
    command: redis-server /etc/redis.conf
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./redis.conf:/etc/redis.conf:ro
EOF


# 9. Redis Config
echo "Writing Redis configuration..."
sudo tee "${LIVEKIT_CONFIG_DIR}/redis.conf" > /dev/null << EOF
bind 127.0.0.1 ::1
protected-mode yes
port 6379
tcp-keepalive 300
EOF

# 10. Systemd Service
echo "Writing systemd service file..."
sudo tee /etc/systemd/system/livekit-docker.service > /dev/null << EOF
[Unit]
Description=LiveKit Server (Docker Compose)
After=docker.service nginx.service
Requires=docker.service nginx.service

[Service]
Type=simple
LimitNOFILE=500000
Restart=always
WorkingDirectory=${LIVEKIT_CONFIG_DIR}
ExecStartPre=/usr/bin/docker compose down
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable livekit-docker nginx
sudo systemctl start livekit-docker

echo "-----------------------------------------------------------------------"
echo "✅ SETUP COMPLETE - NGINX + LIVEKIT"
echo "🌐 Domain: https://${LIVEKIT_DOMAIN}"
echo "🔑 IP: ${LIVEKIT_IP}"
echo "-----------------------------------------------------------------------"

echo "NEXT STEPS (Paste SSL Certs) :"
echo "1. Paste Cert: sudo nano ${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
echo "2. Paste Key:  sudo nano ${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"
echo "3. Restart:    sudo systemctl restart nginx"
echo "-----------------------------------------------------------------------"