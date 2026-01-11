#!/bin/bash

# ==============================================================================
# Configuration Variables
# ==============================================================================
LIVEKIT_DOMAIN="livekit.domain.com"
LIVEKIT_CERTS_DIR="/opt/livekit/certs"
LIVEKIT_CERT_FILE="domain.crt"
LIVEKIT_KEY_FILE="domain.key"
API_KEY="APIkbSL89cHqVXY"
API_SECRET="LNFIALFMmdkUTFRFCvp88BAvifFFF3toPg6I1f41ctK"
LIVEKIT_CONFIG_DIR="/opt/livekit"

# Fetch Public IP
LIVEKIT_PUBLIC_IP="$(curl -s https://ifconfig.me)"

# ==============================================================================
# Execution - Optimized for Fresh Ubuntu
# ==============================================================================

echo "Starting LiveKit setup for ${LIVEKIT_DOMAIN} on fresh Ubuntu..."

# 1. System Updates & Basic Dependencies
sudo apt-get update && sudo apt-get install -y curl sed grep

# 2. CLEANUP: Ensure we don't have directory/file conflicts
# This is critical for fresh installs where Docker might create folders on volume mount
sudo rm -rf "${LIVEKIT_CONFIG_DIR}/caddy.yaml"
sudo rm -rf "${LIVEKIT_CONFIG_DIR}/livekit.yaml"
sudo mkdir -p "${LIVEKIT_CONFIG_DIR}/caddy_data"
sudo mkdir -p "${LIVEKIT_CERTS_DIR}"

# 3. SSL Placeholders
sudo touch "${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
sudo touch "${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"
sudo chmod 755 "${LIVEKIT_CERTS_DIR}"
sudo chmod 644 "${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
sudo chmod 644 "${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"

# 4. Install Docker (Official Docker Script)
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
fi
sudo systemctl enable --now docker

# 5. LiveKit Config
echo "Writing LiveKit configuration..."
sudo tee "${LIVEKIT_CONFIG_DIR}/livekit.yaml" > /dev/null << EOF
port: 7880
bind_addresses:
    - ""
rtc:
    tcp_port: 7881
    udp_port: 7882
    use_external_ip: true
    enable_loopback_candidate: false
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

# 6. Caddy Config (Layer 4 Proxy)
echo "Writing Caddy configuration..."
sudo tee "${LIVEKIT_CONFIG_DIR}/caddy.yaml" > /dev/null << EOF
logging:
  logs:
    default:
      level: INFO
storage:
  "module": "file_system"
  "root": "/data"
apps:
  tls:
    certificates:
      load_files:
        - certificate: /etc/ssl/certs/${LIVEKIT_CERT_FILE}
          key: /etc/ssl/certs/${LIVEKIT_KEY_FILE}
  layer4:
    servers:
      main:
        listen: [":443"]
        routes:
          - match:
            - tls:
                sni: ["${LIVEKIT_DOMAIN}"]
                alpn: ["h2", "http/1.1"]
            handle:
              - handler: tls
                connection_policies:
                  - alpn: ["h2", "http/1.1"]
              - handler: proxy
                upstreams:
                  - dial: ["localhost:7880"]
          - match:
            - tls:
                sni: ["${LIVEKIT_DOMAIN}"]
            handle:
              - handler: tls
              - handler: proxy
                upstreams:
                  - dial: ["localhost:5349"]
EOF

# 7. IP Update Script (Fresh OS safe)
echo "Writing IP update script..."
sudo tee "${LIVEKIT_CONFIG_DIR}/update_ip.sh" > /dev/null << EOF
#!/usr/bin/env bash
ip="${LIVEKIT_PUBLIC_IP}"
if [ -f "${LIVEKIT_CONFIG_DIR}/caddy.yaml" ]; then
    content=\$(cat "${LIVEKIT_CONFIG_DIR}/caddy.yaml")
    echo "\$content" | sed -r "s/dial: \\[\"(localhost|[0-9\\.]+):5349\"\\]/dial: \\[\"\$ip:5349\"\\]/" > "${LIVEKIT_CONFIG_DIR}/caddy.yaml"
fi
EOF

# 8. Docker Compose file
echo "Writing Docker Compose file..."
sudo tee "${LIVEKIT_CONFIG_DIR}/docker-compose.yaml" > /dev/null << EOF
services:
  caddy:
    image: livekit/caddyl4
    command: run --config /etc/caddy.yaml --adapter yaml
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./caddy.yaml:/etc/caddy.yaml
      - ./caddy_data:/data
      - ${LIVEKIT_CERTS_DIR}:/etc/ssl/certs:ro
  livekit:
    image: livekit/livekit-server:latest
    command: --config /etc/livekit.yaml
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
  redis:
    image: redis:7-alpine
    command: redis-server /etc/redis.conf
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./redis.conf:/etc/redis.conf
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
After=docker.service
Requires=docker.service

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

# 11. Start
sudo chmod +x "${LIVEKIT_CONFIG_DIR}/update_ip.sh"
sudo "${LIVEKIT_CONFIG_DIR}/update_ip.sh"

sudo systemctl daemon-reload
sudo systemctl enable livekit-docker
sudo systemctl start livekit-docker

echo "-----------------------------------------------------------------------"
echo "SETUP COMPLETE"
echo "Public IP Detected: ${LIVEKIT_PUBLIC_IP}"
echo "-----------------------------------------------------------------------"
echo "NEXT STEPS:"
echo "1. Paste Cert: sudo nano ${LIVEKIT_CERTS_DIR}/${LIVEKIT_CERT_FILE}"
echo "2. Paste Key:  sudo nano ${LIVEKIT_CERTS_DIR}/${LIVEKIT_KEY_FILE}"
echo "3. Restart:    sudo systemctl restart livekit-docker"
echo "4. Check Logs: sudo docker compose -f ${LIVEKIT_CONFIG_DIR}/docker-compose.yaml logs -f"
echo "-----------------------------------------------------------------------"