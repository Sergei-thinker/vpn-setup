#!/bin/bash
# =============================================================================
# VPN Server Optimization Script
# Запускать на сервере: bash optimize-server.sh
# =============================================================================

set -e

echo "=========================================="
echo "  VPN Server Optimization"
echo "=========================================="

# --- 1. BBR и TCP-тюнинг ---
echo ""
echo "[1/6] Настройка BBR и TCP-тюнинг..."

# Проверить текущий congestion control
echo "  Текущий congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"

# Добавить настройки если их нет
cat >> /etc/sysctl.conf << 'SYSCTL'

# === VPN Optimization (added by optimize-server.sh) ===

# BBR congestion control — критично для lossy мобильных соединений
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP keepalive — быстрее обнаруживать мёртвые соединения
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# TCP буферы — лучшая пропускная способность
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# TCP оптимизации
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_slow_start_after_idle = 0
SYSCTL

sysctl -p
echo "  BBR включён: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "  [OK] TCP-тюнинг применён"

# --- 2. DNS ---
echo ""
echo "[2/6] Настройка DNS..."

# Установить systemd-resolved
apt install -y systemd-resolved > /dev/null 2>&1 || true

# Настроить DNS
cat > /etc/systemd/resolved.conf << 'DNS'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 8.8.4.4
DNSOverTLS=yes
DNS

systemctl enable systemd-resolved --now 2>/dev/null || true
echo "  [OK] DNS настроен (1.1.1.1, 8.8.8.8, DoT)"

# --- 3. Nginx-камуфляж ---
echo ""
echo "[3/6] Установка Nginx-камуфляжа..."

apt install -y nginx > /dev/null 2>&1

# Создать fallback-страницу
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body>
<h1>It works!</h1>
<p>This is the default web page for this server.</p>
</body>
</html>
HTML

# Настроить Nginx как fallback на локальном порту
cat > /etc/nginx/sites-available/fallback << 'NGINX'
server {
    listen 127.0.0.1:8081;
    server_name _;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/fallback /etc/nginx/sites-enabled/fallback
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
echo "  [OK] Nginx слушает на 127.0.0.1:8081"
echo "  >>> ВАЖНО: В 3X-UI добавь fallback 127.0.0.1:8081 в inbound Reality"

# --- 4. Смена учётных данных 3X-UI ---
echo ""
echo "[4/6] Смена учётных данных панели 3X-UI..."
echo "  Текущий логин: admin/admin (НЕБЕЗОПАСНО!)"

# Генерируем случайные данные
NEW_USER="vpnadm_$(openssl rand -hex 3)"
NEW_PASS="$(openssl rand -base64 16)"

x-ui setting -username "$NEW_USER" -password "$NEW_PASS"
x-ui restart

echo "  [OK] Новые учётные данные:"
echo "  ┌─────────────────────────────────────┐"
echo "  │ Логин:  $NEW_USER"
echo "  │ Пароль: $NEW_PASS"
echo "  └─────────────────────────────────────┘"
echo "  >>> ЗАПИШИ ЭТИ ДАННЫЕ! Они больше нигде не сохранены."

# --- 5. Firewall ---
echo ""
echo "[5/6] Настройка firewall (ufw)..."

apt install -y ufw > /dev/null 2>&1

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'LetsEncrypt'
ufw allow 443/tcp comment 'VLESS Reality'
ufw allow 1076/tcp comment '3X-UI Panel'

echo "y" | ufw enable
echo "  [OK] Firewall включён"
ufw status numbered

# --- 6. fail2ban ---
echo ""
echo "[6/6] Установка fail2ban..."

apt install -y fail2ban > /dev/null 2>&1

cat > /etc/fail2ban/jail.local << 'F2B'
[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 3600
findtime = 600
F2B

systemctl enable fail2ban --now
echo "  [OK] fail2ban установлен и настроен"

# --- Итого ---
echo ""
echo "=========================================="
echo "  ГОТОВО! Все оптимизации применены."
echo "=========================================="
echo ""
echo "Проверка:"
echo "  BBR:     $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "  Nginx:   $(systemctl is-active nginx)"
echo "  UFW:     $(ufw status | head -1)"
echo "  fail2ban: $(systemctl is-active fail2ban)"
echo "  x-ui:    $(x-ui status 2>/dev/null | head -1 || echo 'проверь: x-ui status')"
echo ""
echo "СЛЕДУЮЩИЕ ШАГИ:"
echo "  1. В 3X-UI: добавь fallback 127.0.0.1:8081 в inbound Reality"
echo "  2. В 3X-UI: Xray Settings -> DNS -> добавь:"
echo '     {"dns":{"servers":["https+local://1.1.1.1/dns-query"],"queryStrategy":"UseIPv4"}}'
echo "  3. В 3X-UI: создай backup inbound на порту 8443 с SNI dl.google.com"
echo "     (не забудь: ufw allow 8443/tcp)"
echo "  4. На клиенте Hiddify: включи фрагментацию (tlshello, 1-3, 1-3)"
echo "  5. Обнови Hiddify до последней СТАБИЛЬНОЙ версии (не dev!)"
echo ""
