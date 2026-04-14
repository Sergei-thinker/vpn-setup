#!/bin/bash
# =============================================================================
#  DEPLOY RELAY — Настройка Xray Relay на российском VPS (Layer 1)
# =============================================================================
#
#  Сценарий использования:
#    Прямое подключение к шведскому VPS заблокировано ТСПУ →
#    разворачиваем relay на российском VPS → клиент подключается к relay
#    (VLESS Reality, SNI: gosuslugi.ru) → relay пересылает трафик на шведский
#    VPS (VLESS xHTTP packet-up, SNI: microsoft.com) → Интернет.
#
#  Архитектура:
#    Client ──(VLESS Reality)──> RU Relay ──(VLESS xHTTP)──> SE VPS ──> Internet
#    SNI: gosuslugi.ru            SNI: microsoft.com
#
#  Запуск:
#    bash deploy-relay.sh [ОПЦИИ]
#
#  Обязательные параметры:
#    --sweden-ip IP          IP шведского VPS
#    --sweden-uuid UUID      UUID для relay inbound на шведском VPS
#    --sweden-pubkey KEY     Public key relay inbound на шведском VPS
#    --sweden-sid SID        Short ID relay inbound на шведском VPS
#
#  Опциональные:
#    --sweden-port PORT      Порт relay inbound на шведском VPS (по умолчанию: 10443)
#    --relay-uuid UUID       UUID для relay inbound (по умолчанию: авто-генерация)
#    --ssh-port PORT         Новый порт SSH (по умолчанию: оставить текущий)
#    --disable-ssh-password  Отключить вход по паролю SSH (только ключи)
#    --non-interactive       Не спрашивать подтверждения
#    -h, --help              Показать справку
#
#  Создано с помощью Claude Code
#  Дата: 2026-04-08
# =============================================================================

set -euo pipefail

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
CREDENTIALS_FILE="/root/relay-credentials.txt"
MONITOR_SCRIPT="/root/monitor-xray-relay.sh"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

# =============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =============================================================================

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

# Генерация случайной строки заданной длины
rand_string() {
    head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "${1:-8}"
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
        error "Используйте: sudo bash deploy-relay.sh"
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
    echo "Использование: bash deploy-relay.sh [ОПЦИИ]"
    echo ""
    echo "Настройка Xray Relay на российском VPS (Layer 1)."
    echo "Клиент → RU Relay (VLESS Reality) → SE VPS (VLESS xHTTP) → Интернет"
    echo ""
    echo "Обязательные параметры:"
    echo "  --sweden-ip IP          IP шведского VPS"
    echo "  --sweden-uuid UUID      UUID для relay inbound на шведском VPS"
    echo "  --sweden-pubkey KEY     Public key relay inbound на шведском VPS"
    echo "  --sweden-sid SID        Short ID relay inbound на шведском VPS"
    echo ""
    echo "Опциональные параметры:"
    echo "  --sweden-port PORT      Порт relay inbound на шведском VPS (по умолчанию: 10443)"
    echo "  --relay-uuid UUID       UUID для relay inbound (по умолчанию: авто-генерация)"
    echo "  --ssh-port PORT         Новый порт SSH (по умолчанию: оставить текущий)"
    echo "  --disable-ssh-password  Отключить вход по паролю SSH (только ключи)"
    echo "  --non-interactive       Не спрашивать подтверждения"
    echo "  -h, --help              Показать эту справку"
    echo ""
    echo "Пример:"
    echo "  bash deploy-relay.sh \\"
    echo "    --sweden-ip 185.x.x.x \\"
    echo "    --sweden-uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\"
    echo "    --sweden-pubkey XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \\"
    echo "    --sweden-sid abcdef01"
    exit 0
}

# =============================================================================
# ПАРСИНГ АРГУМЕНТОВ
# =============================================================================
SWEDEN_IP=""
SWEDEN_PORT="10443"
SWEDEN_UUID=""
SWEDEN_PUBKEY=""
SWEDEN_SID=""
RELAY_UUID=""
SSH_PORT=""
DISABLE_SSH_PASSWORD=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sweden-ip)            SWEDEN_IP="$2"; shift 2 ;;
        --sweden-port)          SWEDEN_PORT="$2"; shift 2 ;;
        --sweden-uuid)          SWEDEN_UUID="$2"; shift 2 ;;
        --sweden-pubkey)        SWEDEN_PUBKEY="$2"; shift 2 ;;
        --sweden-sid)           SWEDEN_SID="$2"; shift 2 ;;
        --relay-uuid)           RELAY_UUID="$2"; shift 2 ;;
        --ssh-port)             SSH_PORT="$2"; shift 2 ;;
        --disable-ssh-password) DISABLE_SSH_PASSWORD=true; shift ;;
        --non-interactive)      NON_INTERACTIVE=true; shift ;;
        -h|--help)              show_help ;;
        *)                      error "Неизвестная опция: $1"; show_help ;;
    esac
done

# =============================================================================
# ШАГ 1: Проверка окружения и аргументов
# =============================================================================
step 1 "Проверка окружения и аргументов"

check_root
check_os

# Валидация обязательных аргументов
MISSING=""
[ -z "$SWEDEN_IP" ]     && MISSING="${MISSING}  --sweden-ip\n"
[ -z "$SWEDEN_UUID" ]   && MISSING="${MISSING}  --sweden-uuid\n"
[ -z "$SWEDEN_PUBKEY" ] && MISSING="${MISSING}  --sweden-pubkey\n"
[ -z "$SWEDEN_SID" ]    && MISSING="${MISSING}  --sweden-sid\n"

if [ -n "$MISSING" ]; then
    error "Не указаны обязательные параметры:"
    echo -e "$MISSING"
    echo ""
    echo "Используйте --help для справки."
    exit 1
fi

# Генерация UUID для relay если не указан
[ -z "$RELAY_UUID" ] && RELAY_UUID=$(gen_uuid)

# Определить текущий SSH-порт (если --ssh-port не указан)
CURRENT_SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
[ -z "$CURRENT_SSH_PORT" ] && CURRENT_SSH_PORT=22
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="$CURRENT_SSH_PORT"
    SSH_PORT_CHANGED=false
else
    SSH_PORT_CHANGED=true
fi

SERVER_IP=$(get_public_ip)
info "Публичный IP сервера: ${BOLD}$SERVER_IP${NC}"

# Показать параметры и запросить подтверждение
separator
echo -e "${BOLD}Параметры установки:${NC}"
echo ""
echo -e "  ${CYAN}--- Шведский VPS (upstream) ---${NC}"
echo "  IP:             $SWEDEN_IP"
echo "  Port:           $SWEDEN_PORT"
echo "  UUID:           $SWEDEN_UUID"
echo "  Public Key:     $SWEDEN_PUBKEY"
echo "  Short ID:       $SWEDEN_SID"
echo ""
echo -e "  ${CYAN}--- Relay (этот сервер) ---${NC}"
echo "  Relay IP:       $SERVER_IP"
echo "  Relay Port:     443"
echo "  Relay UUID:     $RELAY_UUID"
echo "  Маскировка:     www.gosuslugi.ru"
echo ""
echo -e "  ${CYAN}--- SSH ---${NC}"
echo "  SSH порт:       $SSH_PORT (изменить: $SSH_PORT_CHANGED)"
echo "  Откл. пароль:   $DISABLE_SSH_PASSWORD"
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

success "Проверки пройдены, параметры валидны"

# =============================================================================
# ШАГ 2: Обновление системы и установка зависимостей
# =============================================================================
step 2 "Обновление системы и установка зависимостей"

export DEBIAN_FRONTEND=noninteractive

info "apt update && apt upgrade..."
apt update -y -qq
apt upgrade -y -qq

info "Установка зависимостей..."
apt install -y -qq \
    curl wget unzip openssl ufw cron \
    2>/dev/null

success "Система обновлена, зависимости установлены"

# =============================================================================
# ШАГ 3: Установка Xray-core (standalone, без 3X-UI)
# =============================================================================
step 3 "Установка Xray-core (standalone)"

if [ -f "$XRAY_BIN" ]; then
    CURRENT_VERSION=$($XRAY_BIN version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
    warn "Xray уже установлен (версия: $CURRENT_VERSION). Обновляем..."
fi

info "Скачивание Xray installer..."
XRAY_INSTALL_SCRIPT="/tmp/xray-install.sh"
curl -fsSL "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" -o "$XRAY_INSTALL_SCRIPT"
if [ ! -s "$XRAY_INSTALL_SCRIPT" ] || ! head -1 "$XRAY_INSTALL_SCRIPT" | grep -q '^#!/'; then
    error "Xray installer download failed or file is invalid"
    exit 1
fi
bash "$XRAY_INSTALL_SCRIPT" @ install
rm -f "$XRAY_INSTALL_SCRIPT"

# Проверка установки
if [ ! -f "$XRAY_BIN" ]; then
    error "Xray не найден по пути $XRAY_BIN"
    error "Установка не удалась!"
    exit 1
fi

XRAY_VERSION=$($XRAY_BIN version 2>/dev/null | head -1 || echo "unknown")
success "Xray установлен: $XRAY_VERSION"

# =============================================================================
# ШАГ 4: BBR и TCP-тюнинг
# =============================================================================
step 4 "BBR и TCP-тюнинг"

info "Настройка BBR и TCP-тюнинг..."

# Удалить старые записи если скрипт запускается повторно (идемпотентность)
sed -i '/=== VPN Optimization/,/tcp_slow_start_after_idle/d' /etc/sysctl.conf 2>/dev/null || true

cat >> /etc/sysctl.conf << 'SYSCTL'

# === VPN Optimization (added by deploy-relay.sh) ===
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

# =============================================================================
# ШАГ 5: Генерация ключей для relay inbound
# =============================================================================
step 5 "Генерация ключей для relay inbound"

info "Генерация x25519 keypair..."
KEYPAIR_OUTPUT=$($XRAY_BIN x25519 2>&1)
RELAY_PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep "Private key:" | awk '{print $NF}')
RELAY_PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep "Public key:" | awk '{print $NF}')

if [ -z "$RELAY_PRIVATE_KEY" ] || [ -z "$RELAY_PUBLIC_KEY" ]; then
    error "Не удалось сгенерировать x25519 ключи!"
    error "Вывод xray x25519: $KEYPAIR_OUTPUT"
    exit 1
fi

# Генерация Short ID
RELAY_SHORT_ID=$(gen_short_id)

success "Ключи сгенерированы"
info "  UUID:        $RELAY_UUID"
info "  Public Key:  $RELAY_PUBLIC_KEY"
info "  Short ID:    $RELAY_SHORT_ID"

# =============================================================================
# ШАГ 6: Запись конфигурации Xray
# =============================================================================
step 6 "Запись конфигурации Xray"

# Создать директорию для логов
mkdir -p /var/log/xray

# Создать директорию конфигурации (если нет)
mkdir -p /usr/local/etc/xray

info "Записываем $XRAY_CONFIG..."

cat > "$XRAY_CONFIG" << XRAYEOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "https+local://8.8.8.8/dns-query",
      "localhost"
    ]
  },
  "inbounds": [
    {
      "tag": "relay-inbound",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$RELAY_UUID",
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
          "dest": "www.gosuslugi.ru:443",
          "xver": 0,
          "serverNames": [
            "www.gosuslugi.ru",
            "gosuslugi.ru"
          ],
          "privateKey": "$RELAY_PRIVATE_KEY",
          "shortIds": [
            "$RELAY_SHORT_ID"
          ]
        },
        "tcpSettings": {
          "acceptProxyProtocol": false,
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
      "tag": "relay-to-sweden",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SWEDEN_IP",
            "port": $SWEDEN_PORT,
            "users": [
              {
                "id": "$SWEDEN_UUID",
                "flow": "",
                "encryption": "none"
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
          "publicKey": "$SWEDEN_PUBKEY",
          "shortId": "$SWEDEN_SID",
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
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["relay-inbound"],
        "outboundTag": "relay-to-sweden"
      }
    ]
  }
}
XRAYEOF

# Проверка валидности конфигурации
info "Проверка конфигурации Xray..."
if $XRAY_BIN run -test -config "$XRAY_CONFIG" 2>&1 | grep -q "Configuration OK"; then
    success "Конфигурация Xray валидна"
else
    # Xray может выводить ОК по-разному, просто проверим код возврата
    if $XRAY_BIN run -test -config "$XRAY_CONFIG" > /dev/null 2>&1; then
        success "Конфигурация Xray валидна"
    else
        error "Конфигурация Xray невалидна!"
        $XRAY_BIN run -test -config "$XRAY_CONFIG" 2>&1 || true
        exit 1
    fi
fi

success "Конфигурация записана в $XRAY_CONFIG"

# =============================================================================
# ШАГ 7: Настройка файрвола (UFW)
# =============================================================================
step 7 "Настройка файрвола (UFW)"

info "Настройка UFW..."

# Сброс правил (идемпотентность)
ufw --force reset > /dev/null 2>&1

# Политики по умолчанию
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1

# SSH
ufw allow "$SSH_PORT"/tcp comment 'SSH' > /dev/null 2>&1

# VLESS Reality relay inbound
ufw allow 443/tcp comment 'VLESS Reality relay inbound' > /dev/null 2>&1

# Включить UFW
ufw --force enable > /dev/null 2>&1

success "UFW настроен"
info "Открытые порты: $SSH_PORT (SSH), 443 (VLESS Reality)"

# =============================================================================
# ШАГ 8: Hardening SSH
# =============================================================================
step 8 "Настройка SSH"

# --- Смена SSH-порта (если запрошено) ---
if [ "$SSH_PORT_CHANGED" = true ]; then
    info "Смена SSH-порта: $CURRENT_SSH_PORT -> $SSH_PORT..."

    # Резервная копия sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Изменить порт
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

    # Если строки Port не было — добавить
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
    fi

    success "SSH порт изменён на $SSH_PORT"
else
    info "SSH порт не изменён ($SSH_PORT)"
fi

# --- Отключить вход по паролю (если запрошено) ---
if [ "$DISABLE_SSH_PASSWORD" = true ]; then
    # Резервная копия (если ещё не сделана)
    [ ! -f /etc/ssh/sshd_config.bak ] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
    fi
    warn "Вход по паролю SSH ОТКЛЮЧЁН! Убедитесь, что SSH-ключ добавлен!"
fi

# Перезапуск SSH (НЕ завершаем текущую сессию)
if [ "$SSH_PORT_CHANGED" = true ] || [ "$DISABLE_SSH_PASSWORD" = true ]; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    success "SSH перезапущен"
fi

# =============================================================================
# ШАГ 9: Мониторинг (cron)
# =============================================================================
step 9 "Установка мониторинга Xray"

# Создание скрипта мониторинга
cat > "$MONITOR_SCRIPT" << 'MONITOR'
#!/bin/bash
# =============================================================================
# monitor-xray-relay.sh — Проверка Xray relay и автоматический перезапуск
# Запускается cron-ом каждые 5 минут
# =============================================================================

LOG="/var/log/xray/monitor.log"

if ! systemctl is-active --quiet xray; then
    systemctl restart xray
    echo "$(date '+%Y-%m-%d %H:%M:%S'): xray restarted by monitor" >> "$LOG"
fi

# Ротация лога мониторинга (максимум 1000 строк)
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 1000 ]; then
    tail -500 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi
MONITOR

chmod +x "$MONITOR_SCRIPT"

# Добавить в cron (идемпотентно — сначала удалить старую запись)
CRON_LINE="*/5 * * * * $MONITOR_SCRIPT"
(crontab -l 2>/dev/null | grep -v "monitor-xray-relay" || true; echo "$CRON_LINE") | crontab -

success "Мониторинг настроен: проверка каждые 5 минут"

# =============================================================================
# ШАГ 10: Запуск и вывод credentials
# =============================================================================
step 10 "Запуск Xray и вывод credentials"

info "Запуск Xray..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
sleep 3

# Проверка запуска
XRAY_ACTIVE=false
if systemctl is-active --quiet xray; then
    XRAY_ACTIVE=true
    success "Xray запущен и активен"
else
    error "Xray не запустился!"
    error "Логи:"
    journalctl -u xray --no-pager -n 20 2>/dev/null || true
    cat /var/log/xray/error.log 2>/dev/null | tail -20 || true
fi

# Проверка что порт 443 слушает
PORT_LISTENING=false
if ss -tlnp | grep -q ":443 "; then
    PORT_LISTENING=true
    success "Порт 443 слушает"
else
    warn "Порт 443 не обнаружен в списке слушающих!"
fi

# Формируем VLESS URI для клиентов
RELAY_IP="$SERVER_IP"
VLESS_URI="vless://${RELAY_UUID}@${RELAY_IP}:443?type=tcp&security=reality&sni=www.gosuslugi.ru&fp=chrome&pbk=${RELAY_PUBLIC_KEY}&sid=${RELAY_SHORT_ID}&flow=&encryption=none#Relay-Russia"

# =============================================================================
# СОХРАНЕНИЕ УЧЁТНЫХ ДАННЫХ
# =============================================================================

cat > "$CREDENTIALS_FILE" << CREDENTIALS
# =============================================================================
# RELAY VPS CREDENTIALS — СГЕНЕРИРОВАНО $(date '+%Y-%m-%d %H:%M:%S')
# Relay IP: $RELAY_IP
# =============================================================================

## АРХИТЕКТУРА
# Client ──(VLESS Reality, SNI: gosuslugi.ru)──> RU Relay ($RELAY_IP:443)
#        ──(VLESS xHTTP, SNI: microsoft.com)──> SE VPS ($SWEDEN_IP:$SWEDEN_PORT)
#        ──> Internet

## SSH
ssh -p $SSH_PORT root@$RELAY_IP

## RELAY INBOUND (для клиентов)
Protocol:     VLESS Reality
Address:      $RELAY_IP
Port:         443
UUID:         $RELAY_UUID
Public Key:   $RELAY_PUBLIC_KEY
Short ID:     $RELAY_SHORT_ID
SNI:          www.gosuslugi.ru
Fingerprint:  chrome

## RELAY PRIVATE KEY (НЕ ПЕРЕДАВАТЬ!)
Private Key:  $RELAY_PRIVATE_KEY

## UPSTREAM (шведский VPS)
Address:      $SWEDEN_IP
Port:         $SWEDEN_PORT
UUID:         $SWEDEN_UUID
Public Key:   $SWEDEN_PUBKEY
Short ID:     $SWEDEN_SID

## VLESS URI (скопировать в клиент)
$VLESS_URI

## ПАРАМЕТРЫ
SSH Port:     $SSH_PORT
Xray Config:  $XRAY_CONFIG
Credentials:  $CREDENTIALS_FILE
Monitor:      $MONITOR_SCRIPT
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
if [ "$XRAY_ACTIVE" = true ] && [ "$PORT_LISTENING" = true ]; then
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║           RELAY VPS УСПЕШНО НАСТРОЕН!                   ║"
    echo "  ║           Время: ${MINUTES} мин ${SECONDS_REMAIN} сек                              ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
else
    echo -e "${BOLD}${YELLOW}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║       RELAY НАСТРОЕН, НО ТРЕБУЕТ ПРОВЕРКИ!              ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
fi

echo -e "${BOLD}${CYAN}--- Relay Inbound (для клиентов) ---${NC}"
echo "  Relay IP:     $RELAY_IP"
echo "  Relay Port:   443"
echo "  Relay UUID:   $RELAY_UUID"
echo "  Public Key:   $RELAY_PUBLIC_KEY"
echo "  Short ID:     $RELAY_SHORT_ID"
echo "  Маскировка:   www.gosuslugi.ru"
echo ""

echo -e "${BOLD}${CYAN}--- Upstream (шведский VPS) ---${NC}"
echo "  Sweden IP:    $SWEDEN_IP"
echo "  Sweden Port:  $SWEDEN_PORT"
echo ""

echo -e "${BOLD}${CYAN}--- VLESS URI (скопировать в клиент) ---${NC}"
echo ""
echo -e "${YELLOW}$VLESS_URI${NC}"
echo ""

echo -e "${BOLD}${CYAN}--- SSH ---${NC}"
echo "  ssh -p $SSH_PORT root@$RELAY_IP"
echo ""

separator
echo -e "${GREEN}Все данные сохранены в: ${BOLD}$CREDENTIALS_FILE${NC}"
separator

echo ""
echo -e "${YELLOW}СЛЕДУЮЩИЕ ШАГИ:${NC}"
echo "  1. На шведском VPS: создайте relay inbound (VLESS xHTTP, порт $SWEDEN_PORT)"
echo "     UUID: $SWEDEN_UUID, PublicKey/ShortId от шведского VPS"
echo "  2. Скопируйте VLESS URI в клиент (Hiddify / v2rayNG / Shadowrocket)"
echo "  3. В клиенте включите TLS-фрагментацию: tlshello, 100-400, 1-3"
echo "  4. Проверьте IP на 2ip.ru — должен показывать IP шведского VPS"
echo "  5. Если Layer 1 не нужен — используйте Layer 0 (прямое подключение к SE)"
echo ""
echo -e "${BLUE}Управление:${NC}"
echo "  systemctl status xray    — статус Xray"
echo "  systemctl restart xray   — перезапуск"
echo "  journalctl -u xray -f    — логи в реальном времени"
echo "  cat $CREDENTIALS_FILE    — показать credentials"
echo ""
