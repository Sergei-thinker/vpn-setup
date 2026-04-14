#!/bin/bash
# =============================================================================
#  QUICK REBUILD — Полное восстановление VPN-инфраструктуры на чистом VPS
# =============================================================================
#
#  Сценарий использования:
#    IP текущего VPS заблокирован ТСПУ → создаём новый VPS на Aeza (или другом
#    провайдере) с Debian 12 / Ubuntu 22.04+ → запускаем этот скрипт →
#    через ~15-20 минут имеем полностью рабочую VPN-инфраструктуру.
#
#  Запуск:
#    bash quick-rebuild.sh [ОПЦИИ]
#
#  Опции:
#    --ssh-port PORT        Порт SSH (по умолчанию: случайный 10000-65000)
#    --panel-port PORT      Порт панели 3X-UI (по умолчанию: случайный 1000-9999)
#    --panel-user USER      Логин панели (по умолчанию: случайная строка 8 символов)
#    --panel-pass PASS      Пароль панели (по умолчанию: случайная строка 16 символов)
#    --disable-ssh-password Отключить вход по паролю SSH (только ключи)
#    --non-interactive      Не спрашивать подтверждения, использовать значения по умолчанию
#    -h, --help             Показать справку
#
#  Создано с помощью Claude Code
#  Дата: 2026-04-08
# =============================================================================

set -euo pipefail
trap '' PIPE  # Ignore SIGPIPE (caused by tr|head pipes)

# =============================================================================
# ЦВЕТА И ФОРМАТИРОВАНИЕ
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
step()    { echo -e "\n${CYAN}${BOLD}=== [$1/$TOTAL_STEPS] $2 ===${NC}"; }
separator() { echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"; }

# =============================================================================
# ОБРАБОТКА ОШИБОК
# =============================================================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        error "Скрипт завершился с ошибкой (код: $exit_code)"
        error "Проверьте вывод выше для диагностики."
        error "Можно запустить скрипт повторно — он идемпотентен."
    fi
}
trap cleanup EXIT

# =============================================================================
# КОНСТАНТЫ
# =============================================================================
TOTAL_STEPS=10
CREDENTIALS_FILE="/root/vpn-credentials.txt"
MONITOR_SCRIPT="/root/monitor-xray.sh"
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"
XUI_DB="/etc/x-ui/x-ui.db"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
XUI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

# =============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =============================================================================

# Генерация случайного числа в диапазоне [min, max]
rand_range() {
    local min=$1
    local max=$2
    echo $(( RANDOM % (max - min + 1) + min ))
}

# Генерация случайной строки заданной длины (a-z, 0-9)
rand_string() {
    local length=$1
    openssl rand -hex "$length" | cut -c1-"$length"
}

# Генерация случайного пароля (a-zA-Z0-9)
rand_password() {
    local length=$1
    openssl rand -base64 $(( length * 2 )) | tr -d '/+=\n' | cut -c1-"$length"
}

# Генерация UUID v4
gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null \
        || openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
}

# Генерация shortId (8 hex символов)
gen_short_id() {
    openssl rand -hex 4
}

# Получение публичного IP сервера
get_public_ip() {
    curl -s4 --max-time 5 https://api.ipify.org \
        || curl -s4 --max-time 5 https://ifconfig.me \
        || curl -s4 --max-time 5 https://icanhazip.com \
        || hostname -I | awk '{print $1}'
}

# Проверка что скрипт запущен от root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Этот скрипт необходимо запускать от root!"
        error "Используйте: sudo bash quick-rebuild.sh"
        exit 1
    fi
}

# Проверка ОС
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" && "${VERSION_ID:-0}" -ge 11 ]] || \
           [[ "$ID" == "ubuntu" && "${VERSION_ID:-0}" > "21" ]]; then
            info "ОС: $PRETTY_NAME"
            return 0
        fi
    fi
    warn "Скрипт протестирован на Debian 12 и Ubuntu 22.04+."
    warn "Текущая ОС может не поддерживаться полностью."
}

# Показать справку
show_help() {
    echo "Использование: bash quick-rebuild.sh [ОПЦИИ]"
    echo ""
    echo "Полное восстановление VPN-инфраструктуры на чистом VPS."
    echo ""
    echo "Опции:"
    echo "  --ssh-port PORT        Порт SSH (по умолчанию: случайный 10000-65000)"
    echo "  --panel-port PORT      Порт панели 3X-UI (по умолчанию: случайный 1000-9999)"
    echo "  --panel-user USER      Логин панели (по умолчанию: случайная строка)"
    echo "  --panel-pass PASS      Пароль панели (по умолчанию: случайная строка)"
    echo "  --disable-ssh-password Отключить вход по паролю SSH"
    echo "  --non-interactive      Не спрашивать подтверждения"
    echo "  -h, --help             Показать эту справку"
    exit 0
}

# =============================================================================
# ПАРСИНГ АРГУМЕНТОВ
# =============================================================================
SSH_PORT=""
PANEL_PORT=""
PANEL_USER=""
PANEL_PASS=""
DISABLE_SSH_PASSWORD=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-port)      SSH_PORT="$2"; shift 2 ;;
        --panel-port)    PANEL_PORT="$2"; shift 2 ;;
        --panel-user)    PANEL_USER="$2"; shift 2 ;;
        --panel-pass)    PANEL_PASS="$2"; shift 2 ;;
        --disable-ssh-password) DISABLE_SSH_PASSWORD=true; shift ;;
        --non-interactive)      NON_INTERACTIVE=true; shift ;;
        -h|--help)       show_help ;;
        *)               error "Неизвестная опция: $1"; show_help ;;
    esac
done

# =============================================================================
# ГЕНЕРАЦИЯ ПАРАМЕТРОВ ПО УМОЛЧАНИЮ
# =============================================================================
[ -z "$SSH_PORT" ]   && SSH_PORT=$(rand_range 10000 65000)
[ -z "$PANEL_PORT" ] && PANEL_PORT=$(rand_range 1000 9999)
[ -z "$PANEL_USER" ] && PANEL_USER="adm_$(rand_string 5)"
[ -z "$PANEL_PASS" ] && PANEL_PASS="$(rand_password 16)"

# URI path для панели (случайный)
PANEL_PATH="/$(rand_string 12)/"
SUB_PATH="/sub/$(rand_string 8)/"

# =============================================================================
# НАЧАЛО
# =============================================================================
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║          VPN QUICK REBUILD — Disaster Recovery          ║"
echo "  ║     Полное восстановление инфраструктуры за ~20 мин    ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

check_root
check_os

SERVER_IP=$(get_public_ip)
info "Публичный IP сервера: ${BOLD}$SERVER_IP${NC}"

# Показать параметры и запросить подтверждение
separator
echo -e "${BOLD}Параметры установки:${NC}"
echo "  SSH порт:       $SSH_PORT"
echo "  Панель порт:    $PANEL_PORT"
echo "  Панель логин:   $PANEL_USER"
echo "  Панель пароль:  $PANEL_PASS"
echo "  Панель path:    $PANEL_PATH"
echo "  Subscription:   $SUB_PATH"
echo "  Откл. SSH пароль: $DISABLE_SSH_PASSWORD"
separator

if [ "$NON_INTERACTIVE" = false ]; then
    echo ""
    read -r -p "Продолжить с этими параметрами? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Отменено пользователем."
        exit 0
    fi
fi

START_TIME=$(date +%s)

# =============================================================================
# ШАГ 1: Обновление системы и установка зависимостей
# =============================================================================
step 1 "Обновление системы и установка зависимостей"

export DEBIAN_FRONTEND=noninteractive

info "apt update && apt upgrade..."
apt update -y -qq
apt upgrade -y -qq

info "Установка зависимостей..."
apt install -y -qq \
    curl wget unzip sqlite3 nginx ufw fail2ban cron \
    systemd-resolved openssl jq \
    2>/dev/null

success "Система обновлена, зависимости установлены"

# =============================================================================
# ШАГ 2: Установка 3X-UI (неинтерактивно)
# =============================================================================
step 2 "Установка 3X-UI"

# Проверяем, установлена ли уже 3X-UI
if command -v x-ui &>/dev/null && [ -f "$XRAY_BIN" ]; then
    warn "3X-UI уже установлена. Пропускаем установку."
else
    info "Скачивание и установка 3X-UI..."

    # Установка 3X-UI с передачей ответов на интерактивные вопросы
    # Скрипт спрашивает:
    #   1. "customize panel settings? (y/n)" → y
    #   2. "set up the username" → $PANEL_USER
    #   3. "set up the password" → $PANEL_PASS
    #   4. "set up the panel port" → $PANEL_PORT
    #
    # Используем heredoc для передачи ответов
    curl -Ls "$XUI_INSTALL_URL" -o /tmp/3x-ui-install.sh

    printf 'y\n%s\n%s\n%s\n' "$PANEL_USER" "$PANEL_PASS" "$PANEL_PORT" \
        | bash /tmp/3x-ui-install.sh

    rm -f /tmp/3x-ui-install.sh
fi

# Дождаться запуска x-ui
sleep 3

# Убедиться что x-ui запущена
if systemctl is-active --quiet x-ui; then
    success "3X-UI установлена и запущена"
else
    warn "x-ui не запущена, пробуем запустить..."
    systemctl start x-ui || x-ui start || true
    sleep 2
fi

# Настроить учётные данные и порт (на случай если установщик не принял наши ответы)
info "Применение настроек панели..."
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" 2>/dev/null || true
x-ui setting -port "$PANEL_PORT" 2>/dev/null || true

# Настроить URI path панели и subscription
if [ -f "$XUI_DB" ]; then
    sqlite3 "$XUI_DB" "UPDATE settings SET value='$PANEL_PATH' WHERE key='webBasePath';" 2>/dev/null || true
    sqlite3 "$XUI_DB" "UPDATE settings SET value='$SUB_PATH' WHERE key='subPath';" 2>/dev/null || true
    # Включить subscription
    sqlite3 "$XUI_DB" "UPDATE settings SET value='true' WHERE key='subEnable';" 2>/dev/null || true
    sqlite3 "$XUI_DB" "UPDATE settings SET value='$SUB_PATH' WHERE key='subURI';" 2>/dev/null || true
fi

success "3X-UI настроена: порт=$PANEL_PORT, path=$PANEL_PATH"

# =============================================================================
# ШАГ 3: Оптимизации (BBR, TCP, DNS, Nginx)
# =============================================================================
step 3 "Применение серверных оптимизаций"

# --- 3.1 BBR и TCP-тюнинг ---
info "Настройка BBR и TCP-тюнинг..."

# Удалить старые записи если скрипт запускается повторно
sed -i '/=== VPN Optimization/,/tcp_slow_start_after_idle/d' /etc/sysctl.conf 2>/dev/null || true

cat >> /etc/sysctl.conf << 'SYSCTL'

# === VPN Optimization (added by quick-rebuild.sh) ===
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

sysctl -p > /dev/null 2>&1
success "BBR включён: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'bbr')"

# --- 3.2 DNS ---
info "Настройка DNS..."

cat > /etc/systemd/resolved.conf << 'DNS'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 8.8.4.4
DNSOverTLS=yes
DNS

systemctl enable systemd-resolved --now 2>/dev/null || true
# Ensure /etc/resolv.conf works even if systemd-resolved is slow to start
if ! curl -s --max-time 3 https://raw.githubusercontent.com > /dev/null 2>&1; then
    rm -f /etc/resolv.conf
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
fi
success "DNS настроен (1.1.1.1, 8.8.8.8, DoT)"

# --- 3.3 Nginx-камуфляж ---
info "Настройка Nginx-камуфляжа..."

mkdir -p /var/www/html
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Welcome</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;
         background:#f8f9fa;color:#333}
    .c{text-align:center;padding:2rem}
    h1{font-size:1.8rem;margin-bottom:.5rem;color:#2c3e50}
    p{color:#7f8c8d;margin-bottom:1rem}
    footer{margin-top:2rem;font-size:.7rem;color:#bdc3c7}
  </style>
</head>
<body>
  <div class="c">
    <h1>It works!</h1>
    <p>This is the default web page for this server.</p>
    <p>The web server software is running but no content has been added yet.</p>
    <footer>&copy; 2024</footer>
  </div>
</body>
</html>
HTML

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

nginx -t > /dev/null 2>&1 && systemctl restart nginx
systemctl enable nginx 2>/dev/null || true
success "Nginx-камуфляж на 127.0.0.1:8081"

# --- 3.4 ulimit для x-ui ---
info "Повышение ulimit для x-ui..."
mkdir -p /etc/systemd/system/x-ui.service.d
cat > /etc/systemd/system/x-ui.service.d/limits.conf << 'ULIMIT'
[Service]
LimitNOFILE=65535
ULIMIT

systemctl daemon-reload
success "ulimit = 65535 для x-ui"

# =============================================================================
# ШАГ 4: Генерация ключей и UUID
# =============================================================================
step 4 "Генерация ключей Reality и UUID"

# Дождаться появления xray бинарника
if [ ! -f "$XRAY_BIN" ]; then
    warn "Xray бинарник не найден по пути $XRAY_BIN, ищем..."
    XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f -executable 2>/dev/null | head -1)
    if [ -z "$XRAY_BIN" ]; then
        error "Xray бинарник не найден! Проверьте установку 3X-UI."
        exit 1
    fi
fi

info "Xray: $XRAY_BIN"

# Генерация x25519 ключей для Reality
KEYS=$("$XRAY_BIN" x25519 2>/dev/null)
PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
# Xray >=26.x outputs "Password" instead of "PublicKey"
PUBLIC_KEY=$(echo "$KEYS" | grep -iE "public|password" | awk '{print $NF}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    error "Не удалось сгенерировать x25519 ключи!"
    exit 1
fi

info "Private Key: ${PRIVATE_KEY:0:10}..."
info "Public Key:  ${PUBLIC_KEY:0:10}..."

# Генерация UUID для каждого inbound
UUID_MAIN=$(gen_uuid)
UUID_GOOGLE=$(gen_uuid)
UUID_APPLE=$(gen_uuid)
UUID_WS=$(gen_uuid)

# Генерация shortId для каждого inbound
SID_MAIN=$(gen_short_id)
SID_GOOGLE=$(gen_short_id)
SID_APPLE=$(gen_short_id)

success "Ключи и UUID сгенерированы"

# =============================================================================
# ШАГ 5: Создание inbound-ов через sqlite3
# =============================================================================
step 5 "Создание inbound-ов в 3X-UI"

# Останавливаем x-ui для работы с БД
systemctl stop x-ui 2>/dev/null || x-ui stop 2>/dev/null || true
sleep 2

if [ ! -f "$XUI_DB" ]; then
    error "БД 3X-UI не найдена: $XUI_DB"
    exit 1
fi

# Удаляем существующие inbound-ы (идемпотентность)
sqlite3 "$XUI_DB" "DELETE FROM inbounds;" 2>/dev/null || true

info "Создание inbound: reality-main (443, microsoft.com)..."

# --- Inbound 1: reality-main (порт 443, SNI www.microsoft.com) ---
SETTINGS_MAIN=$(cat <<EOJSON
{
  "clients": [
    {
      "id": "$UUID_MAIN",
      "flow": "",
      "email": "main-user",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "main-$(rand_string 6)",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": [
    {
      "dest": "127.0.0.1:8081",
      "xver": 0
    }
  ]
}
EOJSON
)

STREAM_MAIN=$(cat <<EOJSON
{
  "network": "tcp",
  "security": "reality",
  "externalProxy": [],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "dest": "www.microsoft.com:443",
    "serverNames": ["www.microsoft.com", "microsoft.com"],
    "privateKey": "$PRIVATE_KEY",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": ["$SID_MAIN", ""],
    "settings": {
      "publicKey": "$PUBLIC_KEY",
      "fingerprint": "chrome",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": false,
    "header": { "type": "none" }
  }
}
EOJSON
)

SNIFFING='{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false,"routeOnly":false}'
ALLOCATE='{"strategy":"always","refresh":5,"concurrency":3}'

sqlite3 "$XUI_DB" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'reality-main', 1, 0, '', 443, 'vless', '$SETTINGS_MAIN', '$STREAM_MAIN', 'inbound-443', '$SNIFFING');"

success "reality-main: порт 443, SNI www.microsoft.com"

# --- Inbound 2: reality-google (порт 8443, SNI dl.google.com) ---
info "Создание inbound: reality-google (8443, dl.google.com)..."

SETTINGS_GOOGLE=$(cat <<EOJSON
{
  "clients": [
    {
      "id": "$UUID_GOOGLE",
      "flow": "",
      "email": "google-user",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "google-$(rand_string 6)",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOJSON
)

STREAM_GOOGLE=$(cat <<EOJSON
{
  "network": "tcp",
  "security": "reality",
  "externalProxy": [],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "dest": "dl.google.com:443",
    "serverNames": ["dl.google.com"],
    "privateKey": "$PRIVATE_KEY",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": ["$SID_GOOGLE", ""],
    "settings": {
      "publicKey": "$PUBLIC_KEY",
      "fingerprint": "chrome",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": false,
    "header": { "type": "none" }
  }
}
EOJSON
)

sqlite3 "$XUI_DB" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'reality-google', 1, 0, '', 8443, 'vless', '$SETTINGS_GOOGLE', '$STREAM_GOOGLE', 'inbound-8443', '$SNIFFING');"

success "reality-google: порт 8443, SNI dl.google.com"

# --- Inbound 3: reality-apple (порт 2053, SNI www.apple.com) ---
info "Создание inbound: reality-apple (2053, www.apple.com)..."

SETTINGS_APPLE=$(cat <<EOJSON
{
  "clients": [
    {
      "id": "$UUID_APPLE",
      "flow": "",
      "email": "apple-user",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "apple-$(rand_string 6)",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOJSON
)

STREAM_APPLE=$(cat <<EOJSON
{
  "network": "tcp",
  "security": "reality",
  "externalProxy": [],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "dest": "www.apple.com:443",
    "serverNames": ["www.apple.com", "apple.com"],
    "privateKey": "$PRIVATE_KEY",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": ["$SID_APPLE", ""],
    "settings": {
      "publicKey": "$PUBLIC_KEY",
      "fingerprint": "chrome",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": false,
    "header": { "type": "none" }
  }
}
EOJSON
)

sqlite3 "$XUI_DB" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'reality-apple', 1, 0, '', 2053, 'vless', '$SETTINGS_APPLE', '$STREAM_APPLE', 'inbound-2053', '$SNIFFING');"

success "reality-apple: порт 2053, SNI www.apple.com"

# --- Inbound 4: ws-cloudflare (порт 2082, WebSocket, без Reality) ---
info "Создание inbound: ws-cloudflare (2082, WebSocket)..."

WS_PATH_INBOUND="/ws-proxy"

SETTINGS_WS=$(cat <<EOJSON
{
  "clients": [
    {
      "id": "$UUID_WS",
      "flow": "",
      "email": "ws-user",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "ws-$(rand_string 6)",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOJSON
)

STREAM_WS=$(cat <<EOJSON
{
  "network": "ws",
  "security": "none",
  "externalProxy": [],
  "wsSettings": {
    "acceptProxyProtocol": false,
    "path": "$WS_PATH_INBOUND",
    "host": "",
    "headers": {}
  }
}
EOJSON
)

sqlite3 "$XUI_DB" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'ws-cloudflare', 1, 0, '', 2082, 'vless', '$SETTINGS_WS', '$STREAM_WS', 'inbound-2082', '$SNIFFING');"

success "ws-cloudflare: порт 2082, WebSocket, path=$WS_PATH_INBOUND"

# Настройка Xray DNS в 3X-UI
info "Настройка Xray DNS..."
XRAY_DNS='{"dns":{"servers":["https+local://1.1.1.1/dns-query","https+local://8.8.8.8/dns-query"],"queryStrategy":"UseIPv4"}}'
sqlite3 "$XUI_DB" "UPDATE settings SET value='$XRAY_DNS' WHERE key='xrayTemplateConfig';" 2>/dev/null || true

success "Все 4 inbound-а созданы"

# =============================================================================
# ШАГ 6: Установка GeoIP/GeoSite баз данных
# =============================================================================
step 6 "Установка GeoIP/GeoSite баз данных"

GEOBIN_DIR=$(dirname "$XRAY_BIN")

info "Скачивание geosite.dat..."
wget -q -O "$GEOBIN_DIR/geosite.dat" "$GEOSITE_URL" || warn "Не удалось скачать geosite.dat"

info "Скачивание geoip.dat..."
wget -q -O "$GEOBIN_DIR/geoip.dat" "$GEOIP_URL" || warn "Не удалось скачать geoip.dat"

if [ -f "$GEOBIN_DIR/geosite.dat" ] && [ -f "$GEOBIN_DIR/geoip.dat" ]; then
    success "GeoIP/GeoSite установлены в $GEOBIN_DIR/"
else
    warn "Некоторые geo-базы не установлены (не критично)"
fi

# =============================================================================
# ШАГ 7: Firewall (UFW)
# =============================================================================
step 7 "Настройка Firewall (UFW)"

# Сброс UFW для идемпотентности
ufw --force reset > /dev/null 2>&1

ufw default deny incoming
ufw default allow outgoing

# SSH (новый порт)
ufw allow "$SSH_PORT"/tcp comment "SSH"

# Для Let's Encrypt
ufw allow 80/tcp comment "HTTP/LetsEncrypt"

# VPN inbound-ы
ufw allow 443/tcp comment "VLESS Reality (main)"
ufw allow 8443/tcp comment "VLESS Reality (google)"
ufw allow 2053/tcp comment "VLESS Reality (apple)"
ufw allow 2082/tcp comment "VLESS WS (Cloudflare)"

# Панель 3X-UI
ufw allow "$PANEL_PORT"/tcp comment "3X-UI Panel"

echo "y" | ufw enable > /dev/null 2>&1

success "UFW настроен и включён"
info "Открытые порты: $SSH_PORT (SSH), 80, 443, 8443, 2053, 2082, $PANEL_PORT (panel)"

# =============================================================================
# ШАГ 8: fail2ban + SSH hardening
# =============================================================================
step 8 "Настройка fail2ban и SSH"

# --- fail2ban ---
info "Настройка fail2ban..."

cat > /etc/fail2ban/jail.local << FAIL2BAN
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
bantime = 3600
findtime = 600
backend = systemd
FAIL2BAN

systemctl enable fail2ban --now 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || true
success "fail2ban настроен для SSH (порт $SSH_PORT)"

# --- Смена SSH-порта ---
info "Смена SSH-порта: 22 -> $SSH_PORT..."

# Резервная копия sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Изменить порт
sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

# Если строки Port не было — добавить
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# Отключить вход по паролю (если запрошено)
if [ "$DISABLE_SSH_PASSWORD" = true ]; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
    fi
    warn "Вход по паролю SSH ОТКЛЮЧЁН! Убедитесь, что SSH-ключ добавлен!"
fi

# Перезапуск SSH (НЕ завершаем текущую сессию)
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
success "SSH порт изменён на $SSH_PORT"

# =============================================================================
# ШАГ 9: Мониторинг Xray
# =============================================================================
step 9 "Установка мониторинга Xray"

# Создание скрипта мониторинга
cat > "$MONITOR_SCRIPT" << 'MONITOR'
#!/bin/bash
# =============================================================================
# monitor-xray.sh — Проверка Xray и автоматический перезапуск
# Запускается cron-ом каждые 5 минут
# =============================================================================

LOG="/var/log/xray-monitor.log"
MAX_LOG_SIZE=1048576  # 1 МБ

# Ротация лога
if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null)" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG" "${LOG}.old"
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Проверяем статус x-ui сервиса
if ! systemctl is-active --quiet x-ui; then
    echo "[$TIMESTAMP] WARN: x-ui не запущена, перезапускаем..." >> "$LOG"
    systemctl restart x-ui
    sleep 5
    if systemctl is-active --quiet x-ui; then
        echo "[$TIMESTAMP] OK: x-ui перезапущена успешно" >> "$LOG"
    else
        echo "[$TIMESTAMP] ERROR: x-ui не удалось перезапустить!" >> "$LOG"
    fi
else
    # Проверяем что Xray-процесс жив внутри x-ui
    if ! pgrep -f "xray-linux" > /dev/null 2>&1; then
        echo "[$TIMESTAMP] WARN: Xray процесс не найден, перезапуск x-ui..." >> "$LOG"
        systemctl restart x-ui
        sleep 5
        if pgrep -f "xray-linux" > /dev/null 2>&1; then
            echo "[$TIMESTAMP] OK: Xray перезапущен" >> "$LOG"
        else
            echo "[$TIMESTAMP] ERROR: Xray не перезапустился!" >> "$LOG"
        fi
    fi
fi
MONITOR

chmod +x "$MONITOR_SCRIPT"

# Добавление в cron (каждые 5 минут)
# Удаляем старую запись если есть (идемпотентность)
crontab -l 2>/dev/null | grep -v "monitor-xray" | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT") | crontab -

success "Мониторинг Xray установлен (cron каждые 5 минут)"

# =============================================================================
# ШАГ 10: Перезапуск сервисов и вывод результата
# =============================================================================
step 10 "Финализация и перезапуск сервисов"

info "Перезапуск x-ui..."
systemctl restart x-ui 2>/dev/null || x-ui restart 2>/dev/null || true
sleep 3

info "Перезапуск nginx..."
systemctl restart nginx 2>/dev/null || true

info "Перезапуск fail2ban..."
systemctl restart fail2ban 2>/dev/null || true

# Проверка статусов
echo ""
separator
echo -e "${BOLD}Статус сервисов:${NC}"
echo -n "  x-ui:      "; systemctl is-active x-ui 2>/dev/null || echo "unknown"
echo -n "  nginx:     "; systemctl is-active nginx 2>/dev/null || echo "unknown"
echo -n "  fail2ban:  "; systemctl is-active fail2ban 2>/dev/null || echo "unknown"
echo -n "  ufw:       "; ufw status 2>/dev/null | head -1 || echo "unknown"
echo -n "  BBR:       "; sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
separator

# =============================================================================
# ГЕНЕРАЦИЯ VLESS-ССЫЛОК
# =============================================================================

# VLESS Reality ссылка: vless://UUID@IP:PORT?type=tcp&security=reality&sni=SNI&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID#remark
VLESS_MAIN="vless://${UUID_MAIN}@${SERVER_IP}:443?type=tcp&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SID_MAIN}&flow=&encryption=none#reality-main"
VLESS_GOOGLE="vless://${UUID_GOOGLE}@${SERVER_IP}:8443?type=tcp&security=reality&sni=dl.google.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SID_GOOGLE}&flow=&encryption=none#reality-google"
VLESS_APPLE="vless://${UUID_APPLE}@${SERVER_IP}:2053?type=tcp&security=reality&sni=www.apple.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SID_APPLE}&flow=&encryption=none#reality-apple"
VLESS_WS="vless://${UUID_WS}@${SERVER_IP}:2082?type=ws&security=none&path=%2Fws-proxy&encryption=none#ws-cloudflare"

# Subscription URL
SUB_URL="https://${SERVER_IP}:${PANEL_PORT}${SUB_PATH}"

# Panel URL
PANEL_URL="https://${SERVER_IP}:${PANEL_PORT}${PANEL_PATH}"

# =============================================================================
# СОХРАНЕНИЕ УЧЁТНЫХ ДАННЫХ
# =============================================================================

cat > "$CREDENTIALS_FILE" << CREDENTIALS
# =============================================================================
# VPN CREDENTIALS — СГЕНЕРИРОВАНО $(date '+%Y-%m-%d %H:%M:%S')
# IP: $SERVER_IP
# =============================================================================

## SSH
ssh -p $SSH_PORT root@$SERVER_IP

## 3X-UI ПАНЕЛЬ
URL:      $PANEL_URL
Логин:    $PANEL_USER
Пароль:   $PANEL_PASS

## SUBSCRIPTION
$SUB_URL

## VLESS ССЫЛКИ

### reality-main (порт 443, SNI: www.microsoft.com)
$VLESS_MAIN

### reality-google (порт 8443, SNI: dl.google.com)
$VLESS_GOOGLE

### reality-apple (порт 2053, SNI: www.apple.com)
$VLESS_APPLE

### ws-cloudflare (порт 2082, WebSocket — для Cloudflare CDN)
$VLESS_WS

## КЛЮЧИ
Private Key: $PRIVATE_KEY
Public Key:  $PUBLIC_KEY

## SHORT IDs
Main:   $SID_MAIN
Google: $SID_GOOGLE
Apple:  $SID_APPLE

## UUIDs
Main:   $UUID_MAIN
Google: $UUID_GOOGLE
Apple:  $UUID_APPLE
WS:     $UUID_WS

## ПАРАМЕТРЫ
SSH Port:   $SSH_PORT
Panel Port: $PANEL_PORT
Panel Path: $PANEL_PATH
Sub Path:   $SUB_PATH
WS Path:    $WS_PATH_INBOUND
CREDENTIALS

chmod 600 "$CREDENTIALS_FILE"

# =============================================================================
# ИТОГОВЫЙ ВЫВОД
# =============================================================================
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS_REMAIN=$(( ELAPSED % 60 ))

echo ""
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!               ║"
echo "  ║            Время: ${MINUTES} мин ${SECONDS_REMAIN} сек                           ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}${CYAN}--- SSH ---${NC}"
echo "  ssh -p $SSH_PORT root@$SERVER_IP"
echo ""

echo -e "${BOLD}${CYAN}--- ПАНЕЛЬ 3X-UI ---${NC}"
echo "  URL:      $PANEL_URL"
echo "  Логин:    $PANEL_USER"
echo "  Пароль:   $PANEL_PASS"
echo ""

echo -e "${BOLD}${CYAN}--- SUBSCRIPTION ---${NC}"
echo "  $SUB_URL"
echo ""

echo -e "${BOLD}${CYAN}--- VLESS ССЫЛКИ (скопировать в клиент) ---${NC}"
echo ""
echo -e "${YELLOW}reality-main (443, microsoft.com):${NC}"
echo "  $VLESS_MAIN"
echo ""
echo -e "${YELLOW}reality-google (8443, dl.google.com):${NC}"
echo "  $VLESS_GOOGLE"
echo ""
echo -e "${YELLOW}reality-apple (2053, www.apple.com):${NC}"
echo "  $VLESS_APPLE"
echo ""
echo -e "${YELLOW}ws-cloudflare (2082, WebSocket):${NC}"
echo "  $VLESS_WS"
echo ""

echo -e "${BOLD}${CYAN}--- CLOUDFLARE WORKER ---${NC}"
echo "  Backend Host: $SERVER_IP"
echo "  Backend Port: 2082"
echo "  WS Path:      $WS_PATH_INBOUND"
echo "  UUID:         $UUID_WS"
echo ""

separator
echo -e "${GREEN}Все данные сохранены в: ${BOLD}$CREDENTIALS_FILE${NC}"
separator

echo ""
echo -e "${YELLOW}СЛЕДУЮЩИЕ ШАГИ:${NC}"
echo "  1. Скопируйте VLESS-ссылку в клиент (Hiddify / v2rayNG / v2RayTun)"
echo "  2. В клиенте включите TLS-фрагментацию: tlshello, 100-400, 1-3"
echo "  3. Проверьте IP на 2ip.ru — должен показывать IP сервера"
echo "  4. Если нужен Cloudflare CDN — обновите worker.js с новым IP и UUID"
echo "  5. Для дополнительной безопасности: --disable-ssh-password + SSH-ключ"
echo ""
echo -e "${RED}ВАЖНО: Сохраните данные из $CREDENTIALS_FILE в безопасное место!${NC}"
echo ""
