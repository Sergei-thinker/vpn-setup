#!/bin/bash
# =============================================================================
#  DEPLOY-OLCRTC-SERVER — Установка OlcRTC сервера (Layer 2: WebRTC аварийный)
# =============================================================================
#
#  Устанавливает OlcRTC на VPS для туннелирования через Яндекс.Телемост.
#  Сервер выступает вторым участником WebRTC-конференции, принимает трафик
#  через DataChannel и маршрутизирует его в интернет.
#
#  Использование:
#    bash deploy-olcrtc-server.sh [ОПЦИИ]
#
#  Опции:
#    --conference-id ID    ID конференции Телемост (можно задать позже)
#    --port PORT           Порт SOCKS5h прокси (по умолчанию: 8809)
#    --non-interactive     Без подтверждений
#    -h, --help            Справка
#
#  Требования:
#    - Linux (Debian 12 / Ubuntu 22.04+)
#    - Go 1.21+ (будет установлен автоматически)
#    - Доступ к github.com и zarazaex.xyz
#
#  ОГРАНИЧЕНИЯ:
#    - Конференцию в Телемост нужно создавать вручную (через браузер)
#    - Конференция может истечь — используйте refresh-conference.sh
#    - Это аварийный канал — используйте ТОЛЬКО когда Layer 0-1 не работают
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

TOTAL_STEPS=6

# =============================================================================
# ОБРАБОТКА ОШИБОК
# =============================================================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        error "Скрипт завершился с ошибкой (код: $exit_code)"
        error "Можно запустить скрипт повторно — он идемпотентен."
    fi
}
trap cleanup EXIT

# =============================================================================
# ПАРАМЕТРЫ
# =============================================================================
CONFERENCE_ID=""
SOCKS_PORT=8809
NON_INTERACTIVE=false
OLCRTC_DIR="/opt/olcrtc"
OLCRTC_REPO="https://github.com/zarazaex69/olcRTC.git"
CONFIG_DIR="/etc/olcrtc"

while [[ $# -gt 0 ]]; do
    case $1 in
        --conference-id) CONFERENCE_ID="$2"; shift 2 ;;
        --port)          SOCKS_PORT="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        -h|--help)
            echo "Использование: $0 [--conference-id ID] [--port PORT] [--non-interactive]"
            echo ""
            echo "Устанавливает OlcRTC сервер для аварийного WebRTC-канала (Layer 2)."
            echo "Требует ручного создания конференции в Яндекс.Телемост."
            exit 0
            ;;
        *) error "Неизвестный параметр: $1"; exit 1 ;;
    esac
done

# =============================================================================
# ПРОВЕРКИ
# =============================================================================
if [ "$(id -u)" -ne 0 ]; then
    error "Запустите от root: sudo bash $0"
    exit 1
fi

separator
echo -e "${BOLD}  OlcRTC Server — Layer 2 (Аварийный WebRTC через Телемост)${NC}"
separator
echo ""
info "SOCKS5h порт:    $SOCKS_PORT"
info "Conference ID:   ${CONFERENCE_ID:-'(не задан — настроить позже)'}"
info "Директория:      $OLCRTC_DIR"
echo ""

if ! $NON_INTERACTIVE; then
    read -rp "Продолжить установку? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        info "Отменено."
        exit 0
    fi
fi

# =============================================================================
# ШАГ 1: Установка зависимостей
# =============================================================================
step 1 "Установка зависимостей"

apt update -qq
apt install -y -qq curl wget git > /dev/null 2>&1

# Установка Go (если не установлен или версия < 1.21)
GO_INSTALLED=false
if command -v go &>/dev/null; then
    GO_VER=$(go version | grep -oP '\d+\.\d+' | head -1)
    GO_MAJOR=$(echo "$GO_VER" | cut -d. -f1)
    GO_MINOR=$(echo "$GO_VER" | cut -d. -f2)
    if [ "$GO_MAJOR" -ge 1 ] && [ "$GO_MINOR" -ge 21 ]; then
        GO_INSTALLED=true
        success "Go уже установлен: $(go version)"
    fi
fi

if ! $GO_INSTALLED; then
    info "Установка Go 1.22..."
    GO_TAR="go1.22.0.linux-amd64.tar.gz"
    wget -q "https://go.dev/dl/$GO_TAR" -O "/tmp/$GO_TAR"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/$GO_TAR"
    rm -f "/tmp/$GO_TAR"

    # Добавить в PATH
    if ! grep -q '/usr/local/go/bin' /etc/profile.d/go.sh 2>/dev/null; then
        echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
    fi
    export PATH=$PATH:/usr/local/go/bin

    success "Go установлен: $(go version)"
fi

# =============================================================================
# ШАГ 2: Клонирование/обновление OlcRTC
# =============================================================================
step 2 "Клонирование OlcRTC"

if [ -d "$OLCRTC_DIR/.git" ]; then
    info "Обновление существующего репозитория..."
    cd "$OLCRTC_DIR"
    git pull --quiet 2>/dev/null || warn "git pull не удался, используем текущую версию"
else
    info "Клонирование $OLCRTC_REPO..."
    rm -rf "$OLCRTC_DIR"
    git clone --quiet "$OLCRTC_REPO" "$OLCRTC_DIR" 2>/dev/null || {
        error "Не удалось клонировать репозиторий!"
        error "Проверьте доступ к github.com"
        exit 1
    }
fi

cd "$OLCRTC_DIR"
success "OlcRTC: $(git log --oneline -1 2>/dev/null || echo 'cloned')"

# =============================================================================
# ШАГ 3: Сборка серверного компонента
# =============================================================================
step 3 "Сборка OlcRTC сервера"

# Проект использует Go с pion/webrtc (чистый Go, без cgo)
# Структура: cmd/olcrtc/ — основной бинарник, internal/ — библиотеки
if [ -f "go.mod" ]; then
    info "Go-проект обнаружен (pion/webrtc, чистый Go)..."
    export GOPATH="/root/go"
    export PATH=$PATH:$GOPATH/bin

    # Основная сборка — cmd/olcrtc (server mode)
    if [ -d "cmd/olcrtc" ]; then
        go build -o /usr/local/bin/olcrtc ./cmd/olcrtc || {
            error "Сборка cmd/olcrtc не удалась!"
            info "Пробуем go build ./..."
            go build -o /usr/local/bin/olcrtc ./... || true
        }
    else
        go build -o /usr/local/bin/olcrtc ./... || true
    fi

    # Кросс-компиляция для Windows (olcrtc.exe) — чистый Go, без cgo
    if [ -f /usr/local/bin/olcrtc ]; then
        info "Кросс-компиляция для Windows (GOOS=windows)..."
        GOOS=windows GOARCH=amd64 go build -o "$OLCRTC_DIR/olcrtc.exe" ./cmd/olcrtc 2>/dev/null || \
            GOOS=windows GOARCH=amd64 go build -o "$OLCRTC_DIR/olcrtc.exe" ./... 2>/dev/null || \
            warn "Кросс-компиляция для Windows не удалась (не критично)"
        [ -f "$OLCRTC_DIR/olcrtc.exe" ] && success "Windows binary: $OLCRTC_DIR/olcrtc.exe"
    fi

    if [ -f /usr/local/bin/olcrtc ]; then
        chmod +x /usr/local/bin/olcrtc
        success "Go binary собран: /usr/local/bin/olcrtc"
    fi
fi

# Fallback: Python PoC
if [ ! -f /usr/local/bin/olcrtc ]; then
    info "Настройка Python PoC как fallback..."
    apt install -y -qq python3 python3-pip python3-venv > /dev/null 2>&1

    python3 -m venv "$OLCRTC_DIR/venv" 2>/dev/null || true
    if [ -f "$OLCRTC_DIR/requirements.txt" ]; then
        "$OLCRTC_DIR/venv/bin/pip" install -q -r "$OLCRTC_DIR/requirements.txt" 2>/dev/null || true
    fi

    # Создаём wrapper
    cat > /usr/local/bin/olcrtc << 'PYEOF'
#!/bin/bash
cd /opt/olcrtc
source venv/bin/activate 2>/dev/null || true
exec python3 dcsend.py "$@"
PYEOF
    chmod +x /usr/local/bin/olcrtc
    success "Python PoC настроен как fallback"
fi

# =============================================================================
# ШАГ 4: Конфигурация
# =============================================================================
step 4 "Создание конфигурации"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/conference.env" << EOF
# OlcRTC Conference Configuration
# Обновляйте CONFERENCE_ID при создании новой конференции в Телемост
CONFERENCE_ID=${CONFERENCE_ID}
SOCKS_PORT=${SOCKS_PORT}
# ENCRYPTION_KEY автоматически генерируется Телемостом
ENCRYPTION_KEY=
EOF

chmod 600 "$CONFIG_DIR/conference.env"
success "Конфигурация: $CONFIG_DIR/conference.env"

# =============================================================================
# ШАГ 5: Systemd сервис и хелперы
# =============================================================================
step 5 "Создание systemd сервиса и хелперов"

# Systemd service
cat > /etc/systemd/system/olcrtc-server.service << 'UNIT'
[Unit]
Description=OlcRTC Server — WebRTC tunnel via Yandex Telemost
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/olcrtc/conference.env
ExecStart=/usr/local/bin/olcrtc -mode server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

# НЕ включаем автозапуск — Layer 2 активируется вручную
# systemctl enable olcrtc-server
info "Сервис создан (НЕ включён автозапуск — активировать вручную при необходимости)"

# Хелпер: обновление conference ID
cat > /usr/local/bin/refresh-conference.sh << 'HELPER'
#!/bin/bash
# Обновление ID конференции Телемост для OlcRTC
echo "=== Обновление конференции OlcRTC ==="
echo ""
echo "1. Откройте https://telemost.yandex.ru в браузере"
echo "2. Создайте новую конференцию"
echo "3. Скопируйте ID конференции из URL"
echo ""
read -rp "Введите новый Conference ID: " NEW_ID
read -rp "Введите Encryption Key: " NEW_KEY

if [ -n "$NEW_ID" ]; then
    sed -i "s/^CONFERENCE_ID=.*/CONFERENCE_ID=${NEW_ID}/" /etc/olcrtc/conference.env
    sed -i "s/^ENCRYPTION_KEY=.*/ENCRYPTION_KEY=${NEW_KEY}/" /etc/olcrtc/conference.env
    echo ""
    echo "[OK] Конференция обновлена: $NEW_ID"
    echo "[INFO] Перезапустите сервис: systemctl restart olcrtc-server"
else
    echo "[ERROR] ID не может быть пустым"
    exit 1
fi
HELPER
chmod +x /usr/local/bin/refresh-conference.sh

success "Хелпер создан: refresh-conference.sh"

# =============================================================================
# ШАГ 6: Итог
# =============================================================================
step 6 "Итоговая информация"

separator
echo -e "${BOLD}  OlcRTC Server установлен!${NC}"
separator
echo ""
info "Директория:     $OLCRTC_DIR"
info "Конфигурация:   $CONFIG_DIR/conference.env"
info "Сервис:         olcrtc-server.service (НЕ запущен)"
info "SOCKS5h порт:   $SOCKS_PORT"
echo ""
warn "═══ СЛЕДУЮЩИЕ ШАГИ ═══"
echo ""
echo "  1. Создайте конференцию в Телемост:"
echo "     https://telemost.yandex.ru"
echo ""
echo "  2. Обновите конфигурацию:"
echo "     refresh-conference.sh"
echo ""
echo "  3. Запустите сервер:"
echo "     systemctl start olcrtc-server"
echo ""
echo "  4. На клиенте (Linux/WSL2):"
echo "     all_proxy=socks5h://SERVER_IP:$SOCKS_PORT curl https://ifconfig.me"
echo ""
if [ -f "$OLCRTC_DIR/olcrtc.exe" ]; then
    echo ""
    success "Windows binary готов: $OLCRTC_DIR/olcrtc.exe"
    echo "  Скопируйте на Windows и запустите:"
    echo "    olcrtc.exe -mode cnc -room <ROOM_ID> -key <HEX_KEY> -socks-port 8809"
    echo "  Или положите в директорию проекта рядом с olcrtc-client.bat"
fi
echo ""
warn "Layer 2 — АВАРИЙНЫЙ канал. Используйте только если Layer 0-1 не работают!"
separator
