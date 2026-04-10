#!/bin/bash
# =============================================================================
#  MONITOR-RELAY — Проверка здоровья relay-цепочки (Swedish VPS + Relay VPS)
# =============================================================================
#
#  Запускается локально (или с шведского VPS).
#  Проверяет оба сервера и выводит сводный статус.
#
#  Использование:
#    bash monitor-relay.sh              # Полная проверка
#    bash monitor-relay.sh --quick      # Только ping (без SSH)
#
#  Требования:
#    - SSH ключ для обоих серверов
#    - .env файл с RELAY_HOST, VPN_HOST и т.д.
# =============================================================================

set -uo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()    { echo -e "  ${GREEN}[OK]${NC} $*"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "  ${CYAN}[INFO]${NC} $*"; }

# ---------------------------------------------------------------------------
# Загрузка .env
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# Defaults
VPN_HOST="${VPN_HOST:-}"
VPN_SSH_PORT="${VPN_SSH_PORT:-49152}"
VPN_SSH_USER="${VPN_SSH_USER:-root}"
VPN_SSH_KEY="${VPN_SSH_KEY:-$HOME/.ssh/id_ed25519}"

RELAY_HOST="${RELAY_HOST:-}"
RELAY_SSH_PORT="${RELAY_SSH_PORT:-22}"
RELAY_SSH_USER="${RELAY_SSH_USER:-root}"
RELAY_SSH_KEY="${RELAY_SSH_KEY:-$HOME/.ssh/id_ed25519}"
RELAY_PROVIDER="${RELAY_PROVIDER:-generic}"

YC_FOLDER_ID="${YC_FOLDER_ID:-}"
YC_VM_NAME="${YC_VM_NAME:-vpn-relay}"

QUICK_MODE=false
[ "${1:-}" = "--quick" ] && QUICK_MODE=true

ERRORS=0

# ---------------------------------------------------------------------------
# Проверка одного VPS
# ---------------------------------------------------------------------------
check_vps() {
    local label="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local key="$5"
    local service="$6"  # x-ui или xray

    echo -e "\n${BOLD}=== ${label} [${host}:${port}] ===${NC}"

    if [ -z "$host" ]; then
        warn "Не настроен (HOST пустой)"
        return 1
    fi

    # Шаг 1: TCP-доступность
    if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        ok "SSH порт $port доступен"
    else
        fail "SSH порт $port недоступен"
        ((ERRORS++))
        return 1
    fi

    if $QUICK_MODE; then
        return 0
    fi

    # Шаг 2: SSH + проверка сервиса
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o LogLevel=ERROR"
    local ssh_cmd="ssh $ssh_opts -p $port -i $key ${user}@${host}"

    local status
    status=$($ssh_cmd "systemctl is-active $service 2>/dev/null" 2>/dev/null)
    if [ "$status" = "active" ]; then
        ok "$service: running"
    else
        fail "$service: ${status:-unreachable}"
        ((ERRORS++))
    fi

    # Шаг 3: Xray connections
    local conns
    conns=$($ssh_cmd "ss -tnp 2>/dev/null | grep -c xray || echo 0" 2>/dev/null)
    info "Xray connections: ${conns:-?}"

    # Шаг 4: Uptime
    local uptime_str
    uptime_str=$($ssh_cmd "uptime -p 2>/dev/null || uptime" 2>/dev/null)
    info "Uptime: ${uptime_str:-?}"

    return 0
}

# ---------------------------------------------------------------------------
# Основная проверка
# ---------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   VPN Relay Health Check                 ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo -e "  Время: $(date '+%Y-%m-%d %H:%M:%S')"

check_vps "Swedish VPS (Layer 0/1)" "$VPN_HOST" "$VPN_SSH_PORT" "$VPN_SSH_USER" "$VPN_SSH_KEY" "x-ui"

# Yandex Cloud: дополнительная проверка через yc CLI
if [ "$RELAY_PROVIDER" = "yandex" ] && command -v yc &>/dev/null; then
    echo -e "\n${BOLD}=== Yandex Cloud VM [${YC_VM_NAME}] ===${NC}"
    FOLDER="${YC_FOLDER_ID}"
    if [ -z "$FOLDER" ]; then
        FOLDER=$(yc config get folder-id 2>/dev/null || true)
    fi
    if [ -n "$FOLDER" ]; then
        VM_JSON=$(yc compute instance get --name "$YC_VM_NAME" --folder-id "$FOLDER" --format json 2>/dev/null)
        if [ -n "$VM_JSON" ]; then
            YC_STATUS=$(echo "$VM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null)
            YC_IP=$(echo "$VM_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ifaces=d.get('network_interfaces',[])
if ifaces:
    nat=ifaces[0].get('primary_v4_address',{}).get('one_to_one_nat',{})
    print(nat.get('address',''))
" 2>/dev/null)
            if [ "$YC_STATUS" = "RUNNING" ]; then
                ok "YC VM: RUNNING (IP: ${YC_IP:-?})"
            elif [ "$YC_STATUS" = "STOPPED" ]; then
                fail "YC VM: STOPPED — запустите rotate-relay-yc.sh"
                ((ERRORS++))
            else
                warn "YC VM: $YC_STATUS"
            fi
            # Проверяем совпадение IP с .env
            if [ -n "$YC_IP" ] && [ -n "$RELAY_HOST" ] && [ "$YC_IP" != "$RELAY_HOST" ]; then
                warn "IP mismatch: VM=$YC_IP, .env RELAY_HOST=$RELAY_HOST"
            fi
        else
            fail "YC VM '$YC_VM_NAME' не найдена"
            ((ERRORS++))
        fi
    else
        warn "YC_FOLDER_ID не задан, пропускаю проверку YC"
    fi
fi

check_vps "Russian Relay (Layer 2)" "$RELAY_HOST" "$RELAY_SSH_PORT" "$RELAY_SSH_USER" "$RELAY_SSH_KEY" "xray"

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Все проверки пройдены.${NC}"
else
    echo -e "${RED}${BOLD}Обнаружено проблем: $ERRORS${NC}"
fi

exit $ERRORS
