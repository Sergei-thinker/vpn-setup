#!/bin/bash
# =============================================================================
#  ROTATE-RELAY-YC — Авто-рестарт preemptible VM в Yandex Cloud
# =============================================================================
#
#  Preemptible VM останавливается через 24 часа. Этот скрипт:
#    1. Проверяет статус VM
#    2. Если STOPPED — запускает
#    3. Если IP изменился — обновляет .env и выводит новый VLESS URI
#
#  Использование:
#    bash rotate-relay-yc.sh              # Проверить и перезапустить
#    bash rotate-relay-yc.sh --cron       # Тихий режим (для cron)
#
#  Cron (каждые 5 минут):
#    */5 * * * * /path/to/rotate-relay-yc.sh --cron >> /var/log/yc-relay-rotate.log 2>&1
#
#  Требования:
#    - yc CLI установлен и настроен
#    - .env файл с YC_FOLDER_ID, YC_VM_NAME, RELAY_HOST
# =============================================================================

set -uo pipefail

# =============================================================================
# НАСТРОЙКИ
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_MODE=false
[ "${1:-}" = "--cron" ] && CRON_MODE=true

# Цвета (отключаем в cron-режиме)
if [ "$CRON_MODE" = "true" ] || [ ! -t 1 ]; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" NC=""
else
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    BLUE='\033[0;34m' CYAN='\033[0;36m' BOLD='\033[1m' NC='\033[0m'
fi

info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*"; }
success() { echo -e "${GREEN}[OK]${NC} $(date '+%H:%M:%S') $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }

# =============================================================================
# ЗАГРУЗКА .env
# =============================================================================
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

FOLDER_ID="${YC_FOLDER_ID:-}"
VM_NAME="${YC_VM_NAME:-vpn-relay}"
CURRENT_IP="${RELAY_HOST:-}"

# Relay credentials (для генерации VLESS URI)
RELAY_PORT=15443
RELAY_SNI="yandex.ru"

# =============================================================================
# ПРОВЕРКИ
# =============================================================================
if ! command -v yc &>/dev/null; then
    error "yc CLI не установлен"
    exit 1
fi

if [ -z "$FOLDER_ID" ]; then
    FOLDER_ID=$(yc config get folder-id 2>/dev/null || true)
fi
if [ -z "$FOLDER_ID" ]; then
    error "YC_FOLDER_ID не задан"
    exit 1
fi

# =============================================================================
# ПРОВЕРКА СТАТУСА VM
# =============================================================================
VM_JSON=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json 2>/dev/null)
if [ -z "$VM_JSON" ]; then
    error "VM '$VM_NAME' не найдена в folder '$FOLDER_ID'"
    exit 1
fi

VM_STATUS=$(echo "$VM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
VM_IP=$(echo "$VM_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ifaces = data.get('network_interfaces', [])
if ifaces:
    nat = ifaces[0].get('primary_v4_address', {}).get('one_to_one_nat', {})
    print(nat.get('address', ''))
else:
    print('')
" 2>/dev/null)

# =============================================================================
# ДЕЙСТВИЯ В ЗАВИСИМОСТИ ОТ СТАТУСА
# =============================================================================
case "$VM_STATUS" in
    RUNNING)
        if [ "$CRON_MODE" != "true" ]; then
            success "VM $VM_NAME: RUNNING (IP: ${VM_IP:-unknown})"
        fi
        ;;

    STOPPED)
        warn "VM $VM_NAME остановлена. Запускаю..."
        yc compute instance start --name "$VM_NAME" --folder-id "$FOLDER_ID" --async

        # Ждём запуска (до 60 секунд)
        for i in $(seq 1 12); do
            sleep 5
            NEW_STATUS=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "")
            if [ "$NEW_STATUS" = "RUNNING" ]; then
                break
            fi
        done

        if [ "$NEW_STATUS" = "RUNNING" ]; then
            # Перечитываем IP — мог измениться
            VM_IP=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c "
import sys, json
data = json.load(sys.stdin)
ifaces = data.get('network_interfaces', [])
if ifaces:
    nat = ifaces[0].get('primary_v4_address', {}).get('one_to_one_nat', {})
    print(nat.get('address', ''))
")
            success "VM запущена. IP: $VM_IP"
        else
            error "VM не запустилась за 60 секунд"
            exit 1
        fi
        ;;

    STARTING|UPDATING|RESTARTING)
        info "VM $VM_NAME в процессе: $VM_STATUS"
        exit 0
        ;;

    *)
        error "VM $VM_NAME в неожиданном статусе: $VM_STATUS"
        exit 1
        ;;
esac

# =============================================================================
# ПРОВЕРКА ИЗМЕНЕНИЯ IP
# =============================================================================
if [ -n "$VM_IP" ] && [ "$VM_IP" != "$CURRENT_IP" ]; then
    warn "IP изменился: ${CURRENT_IP:-<пусто>} -> $VM_IP"

    # Обновляем .env
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^RELAY_HOST=" "$ENV_FILE"; then
            sed -i "s|^RELAY_HOST=.*|RELAY_HOST=${VM_IP}|" "$ENV_FILE"
        else
            echo "RELAY_HOST=${VM_IP}" >> "$ENV_FILE"
        fi
        success ".env обновлён: RELAY_HOST=$VM_IP"
    fi

    # Читаем credentials для VLESS URI
    CREDS_FILE="${SCRIPT_DIR}/yc-relay-credentials.txt"
    if [ -f "$CREDS_FILE" ]; then
        RELAY_UUID=$(grep "UUID:" "$CREDS_FILE" | head -1 | awk '{print $NF}')
        RELAY_PUBKEY=$(grep "Public Key:" "$CREDS_FILE" | head -1 | awk '{print $NF}')
        RELAY_SID=$(grep "Short ID:" "$CREDS_FILE" | head -1 | awk '{print $NF}')

        if [ -n "$RELAY_UUID" ] && [ -n "$RELAY_PUBKEY" ] && [ -n "$RELAY_SID" ]; then
            VLESS_URI="vless://${RELAY_UUID}@${VM_IP}:${RELAY_PORT}?type=tcp&security=reality&pbk=${RELAY_PUBKEY}&fp=chrome&sni=${RELAY_SNI}&sid=${RELAY_SID}&spx=#YC-Relay"
            echo ""
            echo -e "${YELLOW}${BOLD}  НОВЫЙ VLESS URI:${NC}"
            echo -e "  ${CYAN}${VLESS_URI}${NC}"
            echo ""
            warn "Обновите VLESS URI в клиенте!"

            # Обновляем credentials file
            sed -i "s|^VM IP:.*|VM IP: ${VM_IP}|" "$CREDS_FILE"
            sed -i "s|vless://.*|${VLESS_URI}|" "$CREDS_FILE"
            sed -i "s|ssh root@.*|ssh root@${VM_IP}|" "$CREDS_FILE"
            sed -i "s|http://[0-9.]*/|http://${VM_IP}/|" "$CREDS_FILE"
        fi
    else
        warn "Credentials файл не найден: $CREDS_FILE"
        warn "Обновите VLESS URI вручную (новый IP: $VM_IP)"
    fi
elif [ "$CRON_MODE" != "true" ]; then
    success "IP не изменился: $VM_IP"
fi
