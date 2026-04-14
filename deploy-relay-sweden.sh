#!/bin/bash
# =============================================================================
#  DEPLOY RELAY SWEDEN — Создание xHTTP Reality inbound для relay-трафика
# =============================================================================
#
#  Этот скрипт запускается на ШВЕДСКОМ VPS, где уже установлена 3X-UI.
#  Создаёт отдельный xHTTP Reality inbound на порте 10443, к которому будет
#  подключаться российский relay-сервер (Layer 1).
#
#  Запуск:
#    bash deploy-relay-sweden.sh [ОПЦИИ]
#
#  Опции:
#    --relay-uuid UUID     UUID для relay-клиента (авто-генерация, если не указан)
#    --short-id SID        ShortId для Reality (авто-генерация, если не указан)
#    --non-interactive     Не спрашивать подтверждения
#    -h, --help            Показать справку
#
#  Безопасно запускать повторно — скрипт идемпотентен.
#
#  Автор: Сергей (создано с Claude Code)
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

# Escape single quotes for safe SQLite interpolation
sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

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
TOTAL_STEPS=6
RELAY_PORT=10443
RELAY_TAG="inbound-relay-xhttp"
RELAY_REMARK="relay-xhttp"
CREDENTIALS_FILE="/root/relay-sweden-credentials.txt"
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"
XUI_DB="/etc/x-ui/x-ui.db"

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

# Генерация случайной строки заданной длины (a-z, 0-9)
rand_string() {
    local length="${1:-8}"
    openssl rand -hex "$length" | cut -c1-"$length"
}

# Получение публичного IP сервера
get_public_ip() {
    curl -s4 --max-time 5 https://api.ipify.org \
        || curl -s4 --max-time 5 https://ifconfig.me \
        || curl -s4 --max-time 5 https://icanhazip.com \
        || hostname -I | awk '{print $1}'
}

# Показать справку
show_help() {
    echo "Использование: bash deploy-relay-sweden.sh [ОПЦИИ]"
    echo ""
    echo "Создание xHTTP Reality inbound на шведском VPS для relay-трафика."
    echo ""
    echo "Опции:"
    echo "  --relay-uuid UUID     UUID для relay-клиента (авто-генерация)"
    echo "  --short-id SID        ShortId для Reality (авто-генерация)"
    echo "  --non-interactive     Не спрашивать подтверждения"
    echo "  -h, --help            Показать эту справку"
    exit 0
}

# =============================================================================
# ПАРСИНГ АРГУМЕНТОВ
# =============================================================================
RELAY_UUID=""
RELAY_SHORT_ID=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --relay-uuid)     RELAY_UUID="$2"; shift 2 ;;
        --short-id)       RELAY_SHORT_ID="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        -h|--help)        show_help ;;
        *)                error "Неизвестная опция: $1"; show_help ;;
    esac
done

# =============================================================================
# НАЧАЛО
# =============================================================================
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║      DEPLOY RELAY SWEDEN — xHTTP Reality inbound        ║"
echo "  ║    Создание relay-канала для российского VPS (Layer 1)  ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

separator
echo -e "  ${BOLD}Порт relay inbound:${NC}  $RELAY_PORT"
echo -e "  ${BOLD}Протокол:${NC}            VLESS + xHTTP + Reality"
echo -e "  ${BOLD}Тег inbound:${NC}         $RELAY_TAG"
if [ -n "$RELAY_UUID" ]; then
    echo -e "  ${BOLD}UUID (указан):${NC}       $RELAY_UUID"
else
    echo -e "  ${BOLD}UUID:${NC}                авто-генерация"
fi
if [ -n "$RELAY_SHORT_ID" ]; then
    echo -e "  ${BOLD}ShortId (указан):${NC}    $RELAY_SHORT_ID"
else
    echo -e "  ${BOLD}ShortId:${NC}             авто-генерация"
fi
separator

if [ "$NON_INTERACTIVE" = false ]; then
    echo ""
    read -rp "Продолжить? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "д" && "$confirm" != "Д" ]]; then
        info "Отменено пользователем."
        exit 0
    fi
fi

# =============================================================================
# ШАГ 1: Проверка окружения
# =============================================================================
step 1 "Проверка окружения"

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
    error "Этот скрипт необходимо запускать от root!"
    error "Используйте: sudo bash deploy-relay-sweden.sh"
    exit 1
fi
success "Запущен от root"

# Проверка x-ui
if ! systemctl is-active --quiet x-ui 2>/dev/null; then
    warn "x-ui не запущен, пытаемся запустить..."
    systemctl start x-ui 2>/dev/null || x-ui start 2>/dev/null || true
    sleep 3
    if ! systemctl is-active --quiet x-ui 2>/dev/null; then
        error "x-ui не установлена или не запускается!"
        error "Сначала установите 3X-UI: bash quick-rebuild.sh"
        exit 1
    fi
fi
success "x-ui запущена и работает"

# Проверка БД x-ui
if [ ! -f "$XUI_DB" ]; then
    error "БД 3X-UI не найдена: $XUI_DB"
    exit 1
fi
success "БД найдена: $XUI_DB"

# Проверка sqlite3
if ! command -v sqlite3 &>/dev/null; then
    info "Установка sqlite3..."
    apt-get update -qq && apt-get install -y -qq sqlite3 >/dev/null 2>&1
fi
success "sqlite3 доступен"

# Поиск xray бинарника
if [ ! -f "$XRAY_BIN" ]; then
    warn "Xray бинарник не найден по пути $XRAY_BIN, ищем..."
    XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f -executable 2>/dev/null | head -1)
    if [ -z "$XRAY_BIN" ]; then
        error "Xray бинарник не найден! Проверьте установку 3X-UI."
        exit 1
    fi
fi
success "Xray: $XRAY_BIN"

# =============================================================================
# ШАГ 2: Генерация ключей для relay-канала
# =============================================================================
step 2 "Генерация ключей для relay-канала"

# Генерация ОТДЕЛЬНОЙ x25519 ключевой пары для relay inbound
info "Генерация x25519 ключей (отдельные от основных inbound-ов)..."
KEYS=$("$XRAY_BIN" x25519 2>/dev/null)
RELAY_PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
# Xray >=26.x outputs "Password" instead of "PublicKey"
RELAY_PUBLIC_KEY=$(echo "$KEYS" | grep -iE "public|password" | awk '{print $NF}')

if [ -z "$RELAY_PRIVATE_KEY" ] || [ -z "$RELAY_PUBLIC_KEY" ]; then
    error "Не удалось сгенерировать x25519 ключи!"
    exit 1
fi

info "Private Key: ${RELAY_PRIVATE_KEY:0:10}..."
info "Public Key:  ${RELAY_PUBLIC_KEY:0:10}..."

# UUID для relay-клиента
[ -z "$RELAY_UUID" ] && RELAY_UUID=$(gen_uuid)
info "UUID: $RELAY_UUID"

# ShortId для Reality
[ -z "$RELAY_SHORT_ID" ] && RELAY_SHORT_ID=$(gen_short_id)
info "ShortId: $RELAY_SHORT_ID"

# SubId для подписки
RELAY_SUB_ID="relay-$(rand_string 6)"
info "SubId: $RELAY_SUB_ID"

success "Ключи и идентификаторы сгенерированы"

# =============================================================================
# ШАГ 3: Создание xHTTP Reality inbound на порте 10443
# =============================================================================
step 3 "Создание xHTTP Reality inbound на порте $RELAY_PORT"

# Останавливаем x-ui для безопасной работы с БД
info "Останавливаем x-ui для работы с БД..."
systemctl stop x-ui 2>/dev/null || x-ui stop 2>/dev/null || true
sleep 2

# Удаляем существующий relay inbound (идемпотентность)
info "Удаление существующего inbound '$RELAY_TAG' (если есть)..."
RELAY_TAG_ESC=$(sql_escape "$RELAY_TAG")
sqlite3 "$XUI_DB" "DELETE FROM inbounds WHERE tag = '$RELAY_TAG_ESC';" 2>/dev/null || true
success "Старый inbound удалён (или не существовал)"

# Формируем JSON для settings
RELAY_SETTINGS=$(cat <<EOJSON
{
  "clients": [
    {
      "id": "$RELAY_UUID",
      "flow": "",
      "email": "relay-user",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "$RELAY_SUB_ID",
      "reset": 0
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOJSON
)

# Формируем JSON для stream_settings
RELAY_STREAM=$(cat <<EOJSON
{
  "network": "xhttp",
  "security": "reality",
  "externalProxy": [],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "dest": "www.microsoft.com:443",
    "serverNames": ["www.microsoft.com", "microsoft.com"],
    "privateKey": "$RELAY_PRIVATE_KEY",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": ["$RELAY_SHORT_ID", ""],
    "settings": {
      "publicKey": "$RELAY_PUBLIC_KEY",
      "fingerprint": "chrome",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "xhttpSettings": {
    "mode": "auto",
    "noGRPCHeader": false,
    "keepAlivePeriod": 0
  }
}
EOJSON
)

RELAY_SNIFFING='{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false,"routeOnly":false}'
RELAY_ALLOCATE='{"strategy":"always","refresh":5,"concurrency":3}'

# Вставка в БД — экранируем строковые значения для SQLite
info "Вставка inbound в БД..."
RELAY_REMARK_ESC=$(sql_escape "$RELAY_REMARK")
RELAY_SETTINGS_ESC=$(sql_escape "$RELAY_SETTINGS")
RELAY_STREAM_ESC=$(sql_escape "$RELAY_STREAM")
RELAY_SNIFFING_ESC=$(sql_escape "$RELAY_SNIFFING")
sqlite3 "$XUI_DB" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, '$RELAY_REMARK_ESC', 1, 0, '', $RELAY_PORT, 'vless', '$RELAY_SETTINGS_ESC', '$RELAY_STREAM_ESC', '$RELAY_TAG_ESC', '$RELAY_SNIFFING_ESC');"

success "Inbound '$RELAY_REMARK' создан: порт $RELAY_PORT, xHTTP Reality"

# =============================================================================
# ШАГ 4: Проверка UFW
# =============================================================================
step 4 "Проверка UFW (порт $RELAY_PORT)"

if command -v ufw &>/dev/null; then
    if ufw status | grep -q "$RELAY_PORT"; then
        success "Порт $RELAY_PORT уже открыт в UFW"
    else
        info "Открываем порт $RELAY_PORT/tcp в UFW..."
        ufw allow "$RELAY_PORT/tcp" comment 'VLESS xHTTP relay inbound' >/dev/null 2>&1
        success "Порт $RELAY_PORT/tcp открыт"
    fi
    # Показать текущее правило
    ufw status | grep "$RELAY_PORT" || true
else
    warn "UFW не установлен. Убедитесь, что порт $RELAY_PORT открыт в файрволе."
fi

# =============================================================================
# ШАГ 5: Перезапуск x-ui
# =============================================================================
step 5 "Перезапуск x-ui"

info "Запуск x-ui..."
systemctl start x-ui 2>/dev/null || x-ui start 2>/dev/null || true
sleep 3

# Проверка статуса
if systemctl is-active --quiet x-ui 2>/dev/null; then
    success "x-ui запущена и работает"
else
    error "x-ui не запустилась! Проверьте логи: journalctl -u x-ui -n 50"
    exit 1
fi

# Проверяем что inbound создан
INBOUND_COUNT=$(sqlite3 "$XUI_DB" "SELECT COUNT(*) FROM inbounds WHERE tag = '$RELAY_TAG_ESC';")
if [ "$INBOUND_COUNT" -eq 1 ]; then
    success "Inbound '$RELAY_TAG' подтверждён в БД"
else
    error "Inbound '$RELAY_TAG' не найден в БД после перезапуска!"
    exit 1
fi

# =============================================================================
# ШАГ 6: Вывод credentials
# =============================================================================
step 6 "Вывод credentials"

SERVER_IP=$(get_public_ip)

echo ""
separator
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║    RELAY CREDENTIALS (сохраните для настройки relay!)   ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}UUID:${NC}         $RELAY_UUID"
echo -e "  ${BOLD}Public Key:${NC}   $RELAY_PUBLIC_KEY"
echo -e "  ${BOLD}Private Key:${NC}  $RELAY_PRIVATE_KEY"
echo -e "  ${BOLD}Short ID:${NC}     $RELAY_SHORT_ID"
echo -e "  ${BOLD}Порт:${NC}         $RELAY_PORT"
echo -e "  ${BOLD}IP сервера:${NC}   $SERVER_IP"
echo -e "  ${BOLD}Протокол:${NC}     VLESS + xHTTP + Reality"
echo -e "  ${BOLD}SNI:${NC}          www.microsoft.com"
echo ""
separator
echo -e "  ${BOLD}${YELLOW}Для deploy-relay.sh на российском VPS используйте:${NC}"
echo ""
echo -e "  ${CYAN}./deploy-relay.sh \\\\${NC}"
echo -e "  ${CYAN}  --sweden-ip $SERVER_IP \\\\${NC}"
echo -e "  ${CYAN}  --sweden-port $RELAY_PORT \\\\${NC}"
echo -e "  ${CYAN}  --sweden-uuid $RELAY_UUID \\\\${NC}"
echo -e "  ${CYAN}  --sweden-pubkey $RELAY_PUBLIC_KEY \\\\${NC}"
echo -e "  ${CYAN}  --sweden-sid $RELAY_SHORT_ID${NC}"
echo ""
separator

# Сохранение в файл
cat > "$CREDENTIALS_FILE" <<EOF
# =============================================================================
# RELAY SWEDEN CREDENTIALS
# Сгенерировано: $(date '+%Y-%m-%d %H:%M:%S')
# Скрипт: deploy-relay-sweden.sh
# =============================================================================

# Параметры relay inbound
RELAY_UUID=$RELAY_UUID
RELAY_PUBLIC_KEY=$RELAY_PUBLIC_KEY
RELAY_PRIVATE_KEY=$RELAY_PRIVATE_KEY
RELAY_SHORT_ID=$RELAY_SHORT_ID
RELAY_PORT=$RELAY_PORT
SERVER_IP=$SERVER_IP

# Команда для deploy-relay.sh на российском VPS:
# ./deploy-relay.sh \\
#   --sweden-ip $SERVER_IP \\
#   --sweden-port $RELAY_PORT \\
#   --sweden-uuid $RELAY_UUID \\
#   --sweden-pubkey $RELAY_PUBLIC_KEY \\
#   --sweden-sid $RELAY_SHORT_ID
EOF

chmod 600 "$CREDENTIALS_FILE"
success "Credentials сохранены в $CREDENTIALS_FILE"

echo ""
echo -e "${BOLD}${GREEN}Готово! Relay inbound на шведском VPS создан.${NC}"
echo -e "${BOLD}Следующий шаг:${NC} запустите deploy-relay.sh на российском VPS."
echo ""
