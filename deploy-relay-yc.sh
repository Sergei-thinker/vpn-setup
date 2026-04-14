#!/bin/bash
# =============================================================================
#  DEPLOY RELAY (YANDEX CLOUD) — Провизия relay VM в Yandex Cloud (Layer 1)
# =============================================================================
#
#  Сценарий использования:
#    ТСПУ включила белые списки на мобильной сети →
#    поднимаем relay VM в Yandex Cloud (IP в белом списке) →
#    клиент подключается к relay (VLESS Reality, SNI: yandex.ru) →
#    relay пересылает на шведский VPS (VLESS xHTTP) → Интернет.
#
#  Архитектура:
#    Client ──(VLESS Reality)──> YC VM:15443 ──(VLESS xHTTP)──> SE VPS:10443 ──> Internet
#    SNI: yandex.ru              SNI: microsoft.com
#
#  Запуск:
#    bash deploy-relay-yc.sh [ОПЦИИ]
#
#  Обязательные параметры (или из .env):
#    --sweden-ip IP          IP шведского VPS
#    --sweden-uuid UUID      UUID relay inbound на шведском VPS
#    --sweden-pubkey KEY     Public key relay inbound на шведском VPS
#    --sweden-sid SID        Short ID relay inbound на шведском VPS
#
#  Опциональные:
#    --sweden-port PORT      Порт relay inbound на шведском VPS (по умолчанию: 10443)
#    --relay-uuid UUID       UUID для relay inbound (по умолчанию: авто-генерация)
#    --folder-id ID          Yandex Cloud folder ID (или YC_FOLDER_ID из .env)
#    --zone ZONE             Зона (по умолчанию: ru-central1-a, или YC_ZONE из .env)
#    --vm-name NAME          Имя VM (по умолчанию: vpn-relay, или YC_VM_NAME из .env)
#    --no-preemptible        Использовать обычную VM (дороже, без рестартов)
#    --static-ip             Зарезервировать статический IP
#    --non-interactive       Не спрашивать подтверждения
#    -h, --help              Показать справку
#
#  Требования:
#    - yc CLI установлен и настроен (yc init)
#    - SSH-ключ (~/.ssh/id_ed25519.pub)
#    - .env файл (опционально, для дефолтных значений)
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
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
step()    { echo -e "\n${CYAN}${BOLD}=== [$1/$TOTAL_STEPS] $2 ===${NC}"; }
separator() { echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"; }

# =============================================================================
# ОБРАБОТКА ОШИБОК
# =============================================================================
TEMP_FILES=()
cleanup() {
    local exit_code=$?
    # Remove temp files
    for f in "${TEMP_FILES[@]}"; do
        [ -f "$f" ] && rm -f "$f"
    done
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
TOTAL_STEPS=9
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/yc-cloud-init.yaml.tpl"
RELAY_PORT=15443
RELAY_SNI="yandex.ru"

# =============================================================================
# ЗАГРУЗКА .env
# =============================================================================
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# =============================================================================
# ПАРАМЕТРЫ ПО УМОЛЧАНИЮ (из .env или дефолты)
# =============================================================================
SWEDEN_IP="${SWEDEN_VPS_IP:-}"
SWEDEN_PORT="${SWEDEN_RELAY_PORT:-10443}"
SWEDEN_UUID="${SWEDEN_RELAY_UUID:-}"
SWEDEN_PUBKEY="${SWEDEN_RELAY_PUBKEY:-}"
SWEDEN_SID="${SWEDEN_RELAY_SID:-}"
RELAY_UUID=""
FOLDER_ID="${YC_FOLDER_ID:-}"
ZONE="${YC_ZONE:-ru-central1-a}"
VM_NAME="${YC_VM_NAME:-vpn-relay}"
PREEMPTIBLE=true
STATIC_IP=false
NON_INTERACTIVE=false
SSH_PUB_KEY_PATH="${YC_SSH_KEY_PUB:-$HOME/.ssh/id_ed25519.pub}"

# =============================================================================
# РАЗБОР АРГУМЕНТОВ
# =============================================================================
show_help() {
    cat << 'HELP'
Использование: bash deploy-relay-yc.sh [ОПЦИИ]

Провизия relay VM в Yandex Cloud для обхода белых списков ТСПУ.

ОБЯЗАТЕЛЬНЫЕ (или из .env):
  --sweden-ip IP          IP шведского VPS
  --sweden-uuid UUID      UUID relay inbound на шведском VPS
  --sweden-pubkey KEY     Public key relay inbound на шведском VPS
  --sweden-sid SID        Short ID relay inbound на шведском VPS

ОПЦИОНАЛЬНЫЕ:
  --sweden-port PORT      Порт на шведском VPS (по умолчанию: 10443)
  --relay-uuid UUID       UUID для relay (по умолчанию: авто-генерация)
  --folder-id ID          Yandex Cloud folder ID
  --zone ZONE             Зона YC (по умолчанию: ru-central1-a)
  --vm-name NAME          Имя VM (по умолчанию: vpn-relay)
  --no-preemptible        Обычная VM (дороже, без рестартов каждые 24ч)
  --static-ip             Зарезервировать статический IP
  --non-interactive       Не спрашивать подтверждения
  -h, --help              Показать справку

ПЕРЕМЕННЫЕ .env:
  SWEDEN_VPS_IP, SWEDEN_RELAY_PORT, SWEDEN_RELAY_UUID
  SWEDEN_RELAY_PUBKEY, SWEDEN_RELAY_SID
  YC_FOLDER_ID, YC_ZONE, YC_VM_NAME, YC_SSH_KEY_PUB
HELP
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sweden-ip)      SWEDEN_IP="$2";      shift 2 ;;
        --sweden-port)    SWEDEN_PORT="$2";     shift 2 ;;
        --sweden-uuid)    SWEDEN_UUID="$2";     shift 2 ;;
        --sweden-pubkey)  SWEDEN_PUBKEY="$2";   shift 2 ;;
        --sweden-sid)     SWEDEN_SID="$2";      shift 2 ;;
        --relay-uuid)     RELAY_UUID="$2";      shift 2 ;;
        --folder-id)      FOLDER_ID="$2";       shift 2 ;;
        --zone)           ZONE="$2";            shift 2 ;;
        --vm-name)        VM_NAME="$2";         shift 2 ;;
        --no-preemptible) PREEMPTIBLE=false;    shift ;;
        --static-ip)      STATIC_IP=true;       shift ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        -h|--help)        show_help; exit 0 ;;
        *) error "Неизвестный аргумент: $1"; show_help; exit 1 ;;
    esac
done

# =============================================================================
# ШАГ 1: ПРОВЕРКА ПРЕРЕКВИЗИТОВ
# =============================================================================
step 1 "Проверка пререквизитов"

# yc CLI
if ! command -v yc &>/dev/null; then
    error "yc CLI не установлен."
    info  "Установка: curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash"
    exit 1
fi
success "yc CLI найден: $(yc version 2>/dev/null | head -1)"

# yc profile
if ! yc config list &>/dev/null; then
    error "yc CLI не настроен. Запустите: yc init"
    exit 1
fi
success "yc CLI настроен"

# folder-id
if [ -z "$FOLDER_ID" ]; then
    FOLDER_ID=$(yc config get folder-id 2>/dev/null || true)
fi
if [ -z "$FOLDER_ID" ]; then
    error "folder-id не задан. Используйте --folder-id или YC_FOLDER_ID в .env"
    exit 1
fi
success "Folder ID: $FOLDER_ID"

# SSH public key
if [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    error "SSH public key не найден: $SSH_PUB_KEY_PATH"
    info  "Создайте: ssh-keygen -t ed25519"
    exit 1
fi
SSH_PUB_KEY=$(cat "$SSH_PUB_KEY_PATH")
success "SSH key: $SSH_PUB_KEY_PATH"

# Cloud-init template
if [ ! -f "$TEMPLATE_FILE" ]; then
    error "Шаблон cloud-init не найден: $TEMPLATE_FILE"
    exit 1
fi
success "Cloud-init шаблон: $TEMPLATE_FILE"

# Sweden VPS parameters
MISSING=""
[ -z "$SWEDEN_IP" ]     && MISSING="${MISSING} --sweden-ip"
[ -z "$SWEDEN_UUID" ]   && MISSING="${MISSING} --sweden-uuid"
[ -z "$SWEDEN_PUBKEY" ] && MISSING="${MISSING} --sweden-pubkey"
[ -z "$SWEDEN_SID" ]    && MISSING="${MISSING} --sweden-sid"
if [ -n "$MISSING" ]; then
    error "Отсутствуют обязательные параметры:${MISSING}"
    info  "Укажите через CLI или в .env (SWEDEN_RELAY_UUID, SWEDEN_RELAY_PUBKEY, SWEDEN_RELAY_SID)"
    info  "Сначала запустите deploy-relay-sweden.sh на шведском VPS для получения этих значений."
    exit 1
fi
success "Sweden VPS: ${SWEDEN_IP}:${SWEDEN_PORT}"

# =============================================================================
# ШАГ 2: ГЕНЕРАЦИЯ CREDENTIALS
# =============================================================================
step 2 "Генерация credentials для relay"

# UUID
if [ -z "$RELAY_UUID" ]; then
    RELAY_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
fi
success "Relay UUID: $RELAY_UUID"

# x25519 ключи — генерируем через xray если есть, иначе через openssl
generate_x25519_keys() {
    # Попытка через xray (если установлен локально)
    if command -v xray &>/dev/null; then
        local output
        output=$(xray x25519 2>/dev/null)
        RELAY_PRIVATE_KEY=$(echo "$output" | grep "Private key:" | awk '{print $NF}')
        RELAY_PUBLIC_KEY=$(echo "$output" | grep "Public key:" | awk '{print $NF}')
        if [ -n "$RELAY_PRIVATE_KEY" ] && [ -n "$RELAY_PUBLIC_KEY" ]; then
            return 0
        fi
    fi

    # Fallback: генерация через Python (всегда доступен)
    read -r RELAY_PRIVATE_KEY RELAY_PUBLIC_KEY <<< "$(python3 -c "
import base64, hashlib, os
# x25519 key generation using Python standard library
private_raw = os.urandom(32)
# Clamp private key per x25519 spec
private_bytes = bytearray(private_raw)
private_bytes[0] &= 248
private_bytes[31] &= 127
private_bytes[31] |= 64
private_b64 = base64.urlsafe_b64encode(bytes(private_bytes)).decode().rstrip('=')
# For public key we need the actual x25519 computation
# Use openssl via subprocess as fallback
import subprocess
proc = subprocess.run(
    ['openssl', 'pkey', '-in', '/dev/stdin', '-pubout', '-outform', 'DER'],
    input=subprocess.run(
        ['openssl', 'genpkey', '-algorithm', 'X25519', '-outform', 'DER'],
        capture_output=True
    ).stdout,
    capture_output=True
)
# Actually, simpler: just generate via openssl directly
proc_priv = subprocess.run(['openssl', 'genpkey', '-algorithm', 'X25519'], capture_output=True, text=True)
proc_pub = subprocess.run(
    ['openssl', 'pkey', '-pubout'],
    input=proc_priv.stdout, capture_output=True, text=True
)
# Extract raw keys from PEM
import subprocess as sp
priv_der = sp.run(['openssl', 'pkey', '-outform', 'DER'], input=proc_priv.stdout.encode(), capture_output=True).stdout
pub_der = sp.run(['openssl', 'pkey', '-pubout', '-outform', 'DER'], input=proc_priv.stdout.encode(), capture_output=True).stdout
# x25519 private key is last 32 bytes of DER, public key is last 32 bytes of DER
priv_raw = priv_der[-32:]
pub_raw = pub_der[-32:]
priv_b64 = base64.urlsafe_b64encode(priv_raw).decode().rstrip('=')
pub_b64 = base64.urlsafe_b64encode(pub_raw).decode().rstrip('=')
print(priv_b64, pub_b64)
")"
}

generate_x25519_keys
success "Relay Private Key: ${RELAY_PRIVATE_KEY:0:10}..."
success "Relay Public Key:  $RELAY_PUBLIC_KEY"

# Short ID
RELAY_SHORT_ID=$(openssl rand -hex 4)
success "Relay Short ID: $RELAY_SHORT_ID"

# =============================================================================
# ШАГ 3: СВОДКА И ПОДТВЕРЖДЕНИЕ
# =============================================================================
step 3 "Сводка конфигурации"

echo ""
separator
echo -e "  ${BOLD}Yandex Cloud VM:${NC}"
echo -e "    Имя:         ${VM_NAME}"
echo -e "    Зона:        ${ZONE}"
echo -e "    Folder:      ${FOLDER_ID}"
echo -e "    Preemptible: ${PREEMPTIBLE}"
echo -e "    Static IP:   ${STATIC_IP}"
echo ""
echo -e "  ${BOLD}Relay Inbound (порт ${RELAY_PORT}):${NC}"
echo -e "    UUID:        ${RELAY_UUID}"
echo -e "    Public Key:  ${RELAY_PUBLIC_KEY}"
echo -e "    Short ID:    ${RELAY_SHORT_ID}"
echo -e "    SNI:         ${RELAY_SNI}"
echo ""
echo -e "  ${BOLD}Sweden Outbound:${NC}"
echo -e "    Address:     ${SWEDEN_IP}:${SWEDEN_PORT}"
echo -e "    UUID:        ${SWEDEN_UUID}"
echo -e "    Public Key:  ${SWEDEN_PUBKEY:0:20}..."
echo -e "    Short ID:    ${SWEDEN_SID}"
separator

if [ "$NON_INTERACTIVE" != "true" ]; then
    echo ""
    read -rp "Продолжить? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        info "Отменено пользователем."
        exit 0
    fi
fi

# =============================================================================
# ШАГ 4: СОЗДАНИЕ СЕТИ (идемпотентно)
# =============================================================================
step 4 "Настройка сети"

NETWORK_NAME="${VM_NAME}-net"
SUBNET_NAME="${VM_NAME}-subnet"
SG_NAME="${VM_NAME}-sg"

# Network
if yc vpc network get --name "$NETWORK_NAME" --folder-id "$FOLDER_ID" &>/dev/null; then
    success "Сеть $NETWORK_NAME уже существует"
else
    info "Создаю сеть $NETWORK_NAME..."
    yc vpc network create \
        --name "$NETWORK_NAME" \
        --folder-id "$FOLDER_ID" \
        --description "VPN relay network"
    success "Сеть $NETWORK_NAME создана"
fi

# Subnet
if yc vpc subnet get --name "$SUBNET_NAME" --folder-id "$FOLDER_ID" &>/dev/null; then
    success "Подсеть $SUBNET_NAME уже существует"
else
    info "Создаю подсеть $SUBNET_NAME..."
    yc vpc subnet create \
        --name "$SUBNET_NAME" \
        --folder-id "$FOLDER_ID" \
        --network-name "$NETWORK_NAME" \
        --zone "$ZONE" \
        --range "10.128.0.0/24"
    success "Подсеть $SUBNET_NAME создана"
fi

# Security Group
if yc vpc security-group get --name "$SG_NAME" --folder-id "$FOLDER_ID" &>/dev/null; then
    success "Security group $SG_NAME уже существует"
else
    info "Создаю security group $SG_NAME..."
    yc vpc security-group create \
        --name "$SG_NAME" \
        --folder-id "$FOLDER_ID" \
        --network-name "$NETWORK_NAME" \
        --description "VPN relay security group" \
        --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0],description=SSH" \
        --rule "direction=ingress,port=80,protocol=tcp,v4-cidrs=[0.0.0.0/0],description=HTTP-decoy" \
        --rule "direction=ingress,port=443,protocol=tcp,v4-cidrs=[0.0.0.0/0],description=HTTPS-decoy" \
        --rule "direction=ingress,port=${RELAY_PORT},protocol=tcp,v4-cidrs=[0.0.0.0/0],description=Xray-relay" \
        --rule "direction=egress,from-port=1,to-port=65535,protocol=tcp,v4-cidrs=[0.0.0.0/0],description=TCP-outbound" \
        --rule "direction=egress,from-port=1,to-port=65535,protocol=udp,v4-cidrs=[0.0.0.0/0],description=UDP-outbound"
    success "Security group $SG_NAME создана"
fi

SG_ID=$(yc vpc security-group get --name "$SG_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# =============================================================================
# ШАГ 5: ГЕНЕРАЦИЯ CLOUD-INIT
# =============================================================================
step 5 "Генерация cloud-init из шаблона"

CLOUD_INIT_FILE=$(mktemp /tmp/yc-cloud-init-XXXXXX.yaml)
TEMP_FILES+=("$CLOUD_INIT_FILE")

cp "$TEMPLATE_FILE" "$CLOUD_INIT_FILE"

# Замена плейсхолдеров
sed -i "s|__RELAY_UUID__|${RELAY_UUID}|g"                "$CLOUD_INIT_FILE"
sed -i "s|__RELAY_PRIVATE_KEY__|${RELAY_PRIVATE_KEY}|g"  "$CLOUD_INIT_FILE"
sed -i "s|__RELAY_PUBLIC_KEY__|${RELAY_PUBLIC_KEY}|g"     "$CLOUD_INIT_FILE"
sed -i "s|__RELAY_SHORT_ID__|${RELAY_SHORT_ID}|g"        "$CLOUD_INIT_FILE"
sed -i "s|__SWEDEN_IP__|${SWEDEN_IP}|g"                  "$CLOUD_INIT_FILE"
sed -i "s|__SWEDEN_PORT__|${SWEDEN_PORT}|g"              "$CLOUD_INIT_FILE"
sed -i "s|__SWEDEN_UUID__|${SWEDEN_UUID}|g"              "$CLOUD_INIT_FILE"
sed -i "s|__SWEDEN_PUBKEY__|${SWEDEN_PUBKEY}|g"          "$CLOUD_INIT_FILE"
sed -i "s|__SWEDEN_SID__|${SWEDEN_SID}|g"                "$CLOUD_INIT_FILE"
sed -i "s|__SSH_PUB_KEY__|${SSH_PUB_KEY}|g"              "$CLOUD_INIT_FILE"

success "Cloud-init сгенерирован: $CLOUD_INIT_FILE"

# =============================================================================
# ШАГ 6: STATIC IP (опционально)
# =============================================================================
step 6 "Настройка IP-адреса"

NAT_SPEC="nat-ip-version=ipv4"
if [ "$STATIC_IP" = "true" ]; then
    STATIC_IP_NAME="${VM_NAME}-ip"
    if yc vpc address get --name "$STATIC_IP_NAME" --folder-id "$FOLDER_ID" &>/dev/null; then
        success "Статический IP $STATIC_IP_NAME уже зарезервирован"
    else
        info "Резервирую статический IP..."
        yc vpc address create \
            --name "$STATIC_IP_NAME" \
            --folder-id "$FOLDER_ID" \
            --zone "$ZONE" \
            --external-ipv4 \
            --description "VPN relay static IP"
        success "Статический IP зарезервирован"
    fi
    STATIC_ADDR=$(yc vpc address get --name "$STATIC_IP_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c "import sys,json; print(json.load(sys.stdin)['external_ipv4_address']['address'])")
    NAT_SPEC="nat-address=$STATIC_ADDR"
    success "Static IP: $STATIC_ADDR"
else
    info "Используется эфемерный IP (будет меняться при рестарте preemptible VM)"
fi

# =============================================================================
# ШАГ 7: СОЗДАНИЕ VM
# =============================================================================
step 7 "Создание VM в Yandex Cloud"

# Проверяем, существует ли VM уже
if yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" &>/dev/null; then
    warn "VM $VM_NAME уже существует."
    VM_STATUS=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
    if [ "$VM_STATUS" = "STOPPED" ]; then
        info "VM остановлена, запускаю..."
        yc compute instance start --name "$VM_NAME" --folder-id "$FOLDER_ID"
        success "VM запущена"
    elif [ "$VM_STATUS" = "RUNNING" ]; then
        success "VM уже запущена"
    else
        warn "VM в статусе: $VM_STATUS"
    fi
else
    info "Создаю VM $VM_NAME..."
    PREEMPTIBLE_FLAG=""
    if [ "$PREEMPTIBLE" = "true" ]; then
        PREEMPTIBLE_FLAG="--preemptible"
    fi

    yc compute instance create \
        --name "$VM_NAME" \
        --folder-id "$FOLDER_ID" \
        --zone "$ZONE" \
        --platform standard-v3 \
        --cores 2 \
        --memory 2 \
        --core-fraction 20 \
        --create-boot-disk "image-folder-id=standard-images,image-family=ubuntu-2204-lts,size=10,type=network-hdd" \
        --network-interface "subnet-name=${SUBNET_NAME},${NAT_SPEC},security-group-ids=${SG_ID}" \
        --hostname "vpn-relay" \
        --metadata-from-file "user-data=${CLOUD_INIT_FILE}" \
        $PREEMPTIBLE_FLAG \
        --description "VPN relay for whitelist bypass" \
        --async

    info "Ожидаю запуск VM..."
    # Ждём до 120 секунд
    for i in $(seq 1 24); do
        sleep 5
        STATUS=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
        if [ "$STATUS" = "RUNNING" ]; then
            break
        fi
        echo -ne "\r  Ожидание... ${i}0s (статус: ${STATUS:-creating})"
    done
    echo ""

    if [ "$STATUS" != "RUNNING" ]; then
        error "VM не запустилась за 120 секунд. Проверьте: yc compute instance get --name $VM_NAME"
        exit 1
    fi
    success "VM $VM_NAME создана и запущена"
fi

# =============================================================================
# ШАГ 8: ИЗВЛЕЧЕНИЕ IP И ОБНОВЛЕНИЕ .env
# =============================================================================
step 8 "Получение IP-адреса VM"

VM_IP=$(yc compute instance get --name "$VM_NAME" --folder-id "$FOLDER_ID" --format json | python3 -c "
import sys, json
data = json.load(sys.stdin)
ifaces = data.get('network_interfaces', [])
if ifaces:
    nat = ifaces[0].get('primary_v4_address', {}).get('one_to_one_nat', {})
    print(nat.get('address', ''))
")

if [ -z "$VM_IP" ]; then
    error "Не удалось получить public IP. Проверьте NAT-настройки VM."
    exit 1
fi
success "VM IP: $VM_IP"

# Обновляем .env
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    if grep -q "^RELAY_HOST=" "$ENV_FILE"; then
        sed -i "s|^RELAY_HOST=.*|RELAY_HOST=${VM_IP}|" "$ENV_FILE"
    else
        echo "RELAY_HOST=${VM_IP}" >> "$ENV_FILE"
    fi

    if grep -q "^RELAY_PROVIDER=" "$ENV_FILE"; then
        sed -i "s|^RELAY_PROVIDER=.*|RELAY_PROVIDER=yandex|" "$ENV_FILE"
    else
        echo "RELAY_PROVIDER=yandex" >> "$ENV_FILE"
    fi
    success ".env обновлён: RELAY_HOST=${VM_IP}, RELAY_PROVIDER=yandex"
else
    warn ".env не найден — создайте вручную или скопируйте .env.example"
fi

# Ждём cloud-init (Xray + nginx)
info "Ожидаю завершение cloud-init (Xray + nginx)..."
info "Это может занять 2-5 минут..."
for i in $(seq 1 30); do
    sleep 10
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o LogLevel=ERROR \
       -i "${SSH_PUB_KEY_PATH%.pub}" "root@${VM_IP}" \
       "systemctl is-active xray" 2>/dev/null | grep -q "active"; then
        break
    fi
    echo -ne "\r  Ожидание cloud-init... ${i}0s"
done
echo ""

# Финальная проверка
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o LogLevel=ERROR \
   -i "${SSH_PUB_KEY_PATH%.pub}" "root@${VM_IP}" \
   "systemctl is-active xray && systemctl is-active nginx" 2>/dev/null | grep -q "active"; then
    success "Xray и Nginx запущены на VM"
else
    warn "Cloud-init может ещё выполняться. Проверьте через пару минут:"
    warn "  ssh root@${VM_IP} 'systemctl status xray nginx'"
fi

# =============================================================================
# ШАГ 9: ВЫВОД РЕЗУЛЬТАТОВ
# =============================================================================
step 9 "Результаты"

# VLESS URI
VLESS_URI="vless://${RELAY_UUID}@${VM_IP}:${RELAY_PORT}?type=tcp&security=reality&pbk=${RELAY_PUBLIC_KEY}&fp=chrome&sni=${RELAY_SNI}&sid=${RELAY_SHORT_ID}&spx=#YC-Relay"

echo ""
separator
echo -e "${GREEN}${BOLD}  RELAY VM РАЗВЁРНУТА УСПЕШНО!${NC}"
separator
echo ""
echo -e "  ${BOLD}VM:${NC}"
echo -e "    IP:          ${VM_IP}"
echo -e "    Name:        ${VM_NAME}"
echo -e "    Zone:        ${ZONE}"
echo -e "    Preemptible: ${PREEMPTIBLE}"
echo ""
echo -e "  ${BOLD}SSH:${NC}"
echo -e "    ssh root@${VM_IP}"
echo ""
echo -e "  ${BOLD}Relay (порт ${RELAY_PORT}):${NC}"
echo -e "    UUID:        ${RELAY_UUID}"
echo -e "    Public Key:  ${RELAY_PUBLIC_KEY}"
echo -e "    Short ID:    ${RELAY_SHORT_ID}"
echo -e "    SNI:         ${RELAY_SNI}"
echo ""
echo -e "  ${BOLD}VLESS URI (для клиента):${NC}"
echo -e "    ${CYAN}${VLESS_URI}${NC}"
echo ""
echo -e "  ${BOLD}Декой:${NC}"
echo -e "    http://${VM_IP}/ — должен показать 'Service Status'"
echo ""

if [ "$PREEMPTIBLE" = "true" ]; then
    echo -e "  ${YELLOW}${BOLD}ВНИМАНИЕ: Preemptible VM!${NC}"
    echo -e "  ${YELLOW}VM будет остановлена через 24ч. IP может измениться.${NC}"
    echo -e "  ${YELLOW}Настройте rotate-relay-yc.sh в cron для авто-рестарта.${NC}"
    echo ""
fi

# Сохраняем credentials
CREDS_FILE="${SCRIPT_DIR}/yc-relay-credentials.txt"
cat > "$CREDS_FILE" << CREDS
=== Yandex Cloud Relay Credentials ===
Date: $(date -Iseconds)
VM Name: ${VM_NAME}
VM IP: ${VM_IP}
Zone: ${ZONE}
Preemptible: ${PREEMPTIBLE}

Relay Inbound:
  Port: ${RELAY_PORT}
  UUID: ${RELAY_UUID}
  Private Key: ${RELAY_PRIVATE_KEY}
  Public Key: ${RELAY_PUBLIC_KEY}
  Short ID: ${RELAY_SHORT_ID}
  SNI: ${RELAY_SNI}

Sweden Outbound:
  Address: ${SWEDEN_IP}:${SWEDEN_PORT}
  UUID: ${SWEDEN_UUID}
  Public Key: ${SWEDEN_PUBKEY}
  Short ID: ${SWEDEN_SID}

VLESS URI:
  ${VLESS_URI}

SSH:
  ssh root@${VM_IP}

Decoy:
  http://${VM_IP}/
CREDS

chmod 600 "$CREDS_FILE"
success "Credentials сохранены: $CREDS_FILE (permissions: 600)"
warn "ВНИМАНИЕ: $CREDS_FILE содержит приватный ключ! Не коммитьте в git!"

separator
echo -e "${GREEN}${BOLD}  Готово! Добавьте VLESS URI в клиент (Hiddify/Shadowrocket/v2rayNG).${NC}"
separator
