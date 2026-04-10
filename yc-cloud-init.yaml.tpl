#cloud-config
# =============================================================================
#  CLOUD-INIT TEMPLATE — Yandex Cloud Relay VM (Layer 2)
# =============================================================================
#
#  Этот шаблон используется deploy-relay-yc.sh для инициализации VM.
#  Плейсхолдеры __PLACEHOLDER__ заменяются скриптом при деплое.
#
#  Плейсхолдеры:
#    __RELAY_UUID__          — UUID для relay inbound
#    __RELAY_PRIVATE_KEY__   — x25519 private key (relay inbound)
#    __RELAY_PUBLIC_KEY__    — x25519 public key (relay inbound, для клиентов)
#    __RELAY_SHORT_ID__      — Short ID (relay inbound)
#    __SWEDEN_IP__           — IP шведского VPS
#    __SWEDEN_PORT__         — Порт relay inbound на шведском VPS (10443)
#    __SWEDEN_UUID__         — UUID relay inbound на шведском VPS
#    __SWEDEN_PUBKEY__       — Public key relay inbound на шведском VPS
#    __SWEDEN_SID__          — Short ID relay inbound на шведском VPS
#    __SSH_PUB_KEY__         — SSH public key для доступа
# =============================================================================

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - openssl
  - nginx
  - cron

users:
  - name: root
    ssh_authorized_keys:
      - __SSH_PUB_KEY__

write_files:
  # --- Xray config (relay: inbound VLESS Reality + outbound xHTTP to Sweden) ---
  - path: /usr/local/etc/xray/config.json
    permissions: '0600'
    content: |
      {
        "log": {
          "loglevel": "warning",
          "access": "/var/log/xray/access.log",
          "error": "/var/log/xray/error.log"
        },
        "inbounds": [
          {
            "tag": "relay-inbound",
            "port": 15443,
            "protocol": "vless",
            "settings": {
              "clients": [
                {
                  "id": "__RELAY_UUID__",
                  "flow": ""
                }
              ],
              "decryption": "none"
            },
            "streamSettings": {
              "network": "tcp",
              "security": "reality",
              "realitySettings": {
                "show": false,
                "dest": "yandex.ru:443",
                "xver": 0,
                "serverNames": [
                  "yandex.ru",
                  "www.yandex.ru",
                  "ya.ru"
                ],
                "privateKey": "__RELAY_PRIVATE_KEY__",
                "shortIds": [
                  "__RELAY_SHORT_ID__"
                ]
              },
              "tcpSettings": {
                "header": {
                  "type": "none"
                }
              }
            },
            "sniffing": {
              "enabled": true,
              "destOverride": [
                "http",
                "tls",
                "quic"
              ]
            }
          }
        ],
        "outbounds": [
          {
            "tag": "to-sweden",
            "protocol": "vless",
            "settings": {
              "vnext": [
                {
                  "address": "__SWEDEN_IP__",
                  "port": __SWEDEN_PORT__,
                  "users": [
                    {
                      "id": "__SWEDEN_UUID__",
                      "encryption": "none",
                      "flow": ""
                    }
                  ]
                }
              ]
            },
            "streamSettings": {
              "network": "xhttp",
              "security": "reality",
              "realitySettings": {
                "show": false,
                "fingerprint": "chrome",
                "serverName": "www.microsoft.com",
                "publicKey": "__SWEDEN_PUBKEY__",
                "shortId": "__SWEDEN_SID__",
                "spiderX": ""
              },
              "xhttpSettings": {
                "mode": "packet-up"
              }
            }
          },
          {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {}
          },
          {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {}
          }
        ],
        "routing": {
          "domainStrategy": "AsIs",
          "rules": [
            {
              "type": "field",
              "inboundTag": [
                "relay-inbound"
              ],
              "outboundTag": "to-sweden"
            }
          ]
        }
      }

  # --- Nginx decoy site ---
  - path: /var/www/html/index.html
    permissions: '0644'
    content: |
      <!DOCTYPE html>
      <html lang="ru">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Server Status</title>
          <style>
              body { font-family: -apple-system, sans-serif; max-width: 600px; margin: 100px auto; text-align: center; color: #333; }
              .status { color: #28a745; font-size: 1.2em; }
              .info { color: #666; margin-top: 20px; font-size: 0.9em; }
          </style>
      </head>
      <body>
          <h1>Service Status</h1>
          <p class="status">All systems operational</p>
          <p class="info">Monitoring endpoint &mdash; no user-facing content.</p>
      </body>
      </html>

  # --- Nginx config ---
  - path: /etc/nginx/sites-available/default
    permissions: '0644'
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name _;
          root /var/www/html;
          index index.html;

          location / {
              try_files $uri $uri/ =404;
          }

          # Health check endpoint
          location /health {
              access_log off;
              return 200 "ok\n";
              add_header Content-Type text/plain;
          }
      }

  # --- Xray monitoring script ---
  - path: /root/monitor-xray.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Auto-restart Xray if not running
      if ! systemctl is-active --quiet xray; then
          echo "$(date): Xray down, restarting..." >> /var/log/xray/monitor.log
          systemctl restart xray
          sleep 2
          if systemctl is-active --quiet xray; then
              echo "$(date): Xray restarted successfully" >> /var/log/xray/monitor.log
          else
              echo "$(date): Xray FAILED to restart" >> /var/log/xray/monitor.log
          fi
      fi

  # --- BBR sysctl ---
  - path: /etc/sysctl.d/99-bbr-relay.conf
    permissions: '0644'
    content: |
      # BBR congestion control
      net.core.default_qdisc = fq
      net.ipv4.tcp_congestion_control = bbr
      # TCP keepalive
      net.ipv4.tcp_keepalive_time = 600
      net.ipv4.tcp_keepalive_intvl = 30
      net.ipv4.tcp_keepalive_probes = 10
      # Buffer optimization
      net.core.rmem_max = 16777216
      net.core.wmem_max = 16777216
      net.ipv4.tcp_rmem = 4096 87380 16777216
      net.ipv4.tcp_wmem = 4096 65536 16777216
      # Connection tracking
      net.ipv4.tcp_max_syn_backlog = 8192
      net.core.somaxconn = 8192
      net.ipv4.tcp_slow_start_after_idle = 0
      net.ipv4.tcp_tw_reuse = 1

runcmd:
  # --- Apply sysctl ---
  - sysctl --system

  # --- Create log directory (writable by xray/nobody) ---
  - mkdir -p /var/log/xray
  - chown -R nobody:nogroup /var/log/xray

  # --- Install Xray ---
  - bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  # --- Enable and start services ---
  - systemctl enable xray
  - systemctl start xray
  - systemctl enable nginx
  - systemctl restart nginx

  # --- Monitoring cron (every 5 minutes) ---
  - (crontab -l 2>/dev/null; echo '*/5 * * * * /root/monitor-xray.sh') | crontab -

  # --- Log rotation for Xray ---
  - |
    cat > /etc/logrotate.d/xray << 'LOGROTATE'
    /var/log/xray/*.log {
        daily
        rotate 3
        compress
        missingok
        notifempty
        postrotate
            systemctl restart xray
        endscript
    }
    LOGROTATE

  # --- Write credentials file ---
  - |
    cat > /root/relay-credentials.txt << 'CREDS'
    === Yandex Cloud Relay Credentials ===
    Date: $(date -Iseconds)
    UUID: __RELAY_UUID__
    Public Key: __RELAY_PUBLIC_KEY__
    Short ID: __RELAY_SHORT_ID__
    Port: 15443
    SNI: yandex.ru
    Dest: Sweden __SWEDEN_IP__:__SWEDEN_PORT__
    CREDS
