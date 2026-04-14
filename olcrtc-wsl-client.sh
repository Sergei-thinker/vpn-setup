#!/bin/bash
# =============================================================================
#  OLCRTC-WSL-CLIENT — Клиент OlcRTC для WSL2 (Layer 2 аварийный)
# =============================================================================
#
#  Запускается ВНУТРИ WSL2 на Windows.
#  Подключается к OlcRTC серверу через Яндекс.Телемост WebRTC.
#  Предоставляет SOCKS5h прокси на localhost:8809 (доступен с Windows хоста).
#
#  Использование:
#    bash olcrtc-wsl-client.sh                    # Интерактивный режим
#    bash olcrtc-wsl-client.sh --id CONF_ID --key KEY  # С параметрами
#
#  На Windows (через Hiddify):
#    1. Запустите этот скрипт в WSL2
#    2. В Hiddify добавьте SOCKS5 прокси: 127.0.0.1:8809
#    3. Весь трафик пойдёт через WebRTC тоннель
#
#  Создано с помощью Claude Code
#  Дата: 2026-04-08
# =============================================================================

set -euo pipefail

# Цвета
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

# =============================================================================
# ПАРАМЕТРЫ
# =============================================================================
CONFERENCE_ID=""
ENCRYPTION_KEY=""
SOCKS_PORT=8809
OLCRTC_DIR="$HOME/olcrtc"
OLCRTC_REPO="https://github.com/zarazaex69/olcRTC.git"

while [[ $# -gt 0 ]]; do
    case $1 in
        --id)   CONFERENCE_ID="$2"; shift 2 ;;
        --key)  ENCRYPTION_KEY="$2"; shift 2 ;;
        --port) SOCKS_PORT="$2"; shift 2 ;;
        -h|--help)
            echo "Использование: $0 [--id CONFERENCE_ID] [--key ENCRYPTION_KEY] [--port PORT]"
            echo ""
            echo "OlcRTC клиент для WSL2 — аварийный VPN через Яндекс.Телемост"
            echo "SOCKS5h прокси будет доступен на localhost:$SOCKS_PORT"
            exit 0
            ;;
        *) error "Неизвестный параметр: $1"; exit 1 ;;
    esac
done

# =============================================================================
# БАННЕР
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║  OlcRTC Client — Layer 2 Emergency WebRTC   ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# ШАГ 1: Установка зависимостей
# =============================================================================
info "Проверка зависимостей..."

# Go
if ! command -v go &>/dev/null; then
    info "Установка Go..."
    sudo apt update -qq 2>/dev/null
    sudo apt install -y -qq golang-go 2>/dev/null || {
        # Ручная установка
        GO_TAR="go1.22.0.linux-amd64.tar.gz"
        wget -q "https://go.dev/dl/$GO_TAR" -O "/tmp/$GO_TAR"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "/tmp/$GO_TAR"
        rm -f "/tmp/$GO_TAR"
        export PATH=$PATH:/usr/local/go/bin
    }
    success "Go: $(go version)"
else
    success "Go: $(go version)"
fi

# Git
if ! command -v git &>/dev/null; then
    sudo apt install -y -qq git 2>/dev/null
fi

# =============================================================================
# ШАГ 2: Клонирование/обновление OlcRTC
# =============================================================================
if [ -d "$OLCRTC_DIR/.git" ]; then
    info "Обновление OlcRTC..."
    cd "$OLCRTC_DIR"
    git pull --quiet 2>/dev/null || warn "git pull не удался"
else
    info "Клонирование OlcRTC..."
    git clone --quiet "$OLCRTC_REPO" "$OLCRTC_DIR" 2>/dev/null || {
        error "Не удалось клонировать OlcRTC!"
        error "Проверьте доступ к github.com"
        exit 1
    }
fi

cd "$OLCRTC_DIR"
success "OlcRTC: $(git log --oneline -1 2>/dev/null || echo 'ready')"

# =============================================================================
# ШАГ 3: Сборка клиента
# =============================================================================
info "Сборка клиента..."

if [ -f "go.mod" ]; then
    go build -o "$OLCRTC_DIR/olcrtc-client" ./... 2>/dev/null || {
        # Попробуем Python fallback
        if [ -f "dcsend.py" ] || [ -f "poc.py" ]; then
            warn "Go сборка не удалась, используем Python PoC"
            sudo apt install -y -qq python3 python3-pip 2>/dev/null
            if [ -f "requirements.txt" ]; then
                pip3 install -q -r requirements.txt 2>/dev/null || true
            fi
        else
            error "Сборка не удалась!"
            exit 1
        fi
    }
fi

if [ -f "$OLCRTC_DIR/olcrtc-client" ]; then
    success "Клиент собран: $OLCRTC_DIR/olcrtc-client"
fi

# =============================================================================
# ШАГ 4: Получение Conference ID
# =============================================================================
if [ -z "$CONFERENCE_ID" ]; then
    echo ""
    warn "Нужен ID конференции из Яндекс.Телемост"
    echo ""
    echo "  1. Откройте https://telemost.yandex.ru"
    echo "  2. Создайте новую конференцию"
    echo "  3. Скопируйте ID из URL"
    echo ""
    read -rp "  Conference ID: " CONFERENCE_ID

    if [ -z "$CONFERENCE_ID" ]; then
        error "Conference ID обязателен!"
        exit 1
    fi
fi

if [ -z "$ENCRYPTION_KEY" ]; then
    read -rp "  Encryption Key: " ENCRYPTION_KEY
fi

# =============================================================================
# ШАГ 5: Запуск SOCKS5h прокси
# =============================================================================
echo ""
info "Запуск OlcRTC клиента..."
info "Conference: $CONFERENCE_ID"
info "SOCKS5h прокси: 0.0.0.0:$SOCKS_PORT"
echo ""
success "═══════════════════════════════════════════════"
success "  SOCKS5 прокси доступен на localhost:$SOCKS_PORT"
success ""
success "  Проверка:"
success "    curl --socks5h localhost:$SOCKS_PORT https://ifconfig.me"
success ""
success "  Для Hiddify (Windows):"
success "    Добавить SOCKS5 прокси → 127.0.0.1:$SOCKS_PORT"
success "═══════════════════════════════════════════════"
echo ""

# Запуск (зависит от доступного бинарника)
if [ -f "$OLCRTC_DIR/olcrtc-client" ]; then
    exec "$OLCRTC_DIR/olcrtc-client" --conference "$CONFERENCE_ID" --key "$ENCRYPTION_KEY" --port "$SOCKS_PORT" --bind "0.0.0.0"
elif [ -f "$OLCRTC_DIR/cnc.py" ]; then
    exec python3 "$OLCRTC_DIR/cnc.py" "$CONFERENCE_ID" "$ENCRYPTION_KEY" "$SOCKS_PORT"
elif [ -f "$OLCRTC_DIR/dcsend.py" ]; then
    exec python3 "$OLCRTC_DIR/dcsend.py" "$CONFERENCE_ID" "$ENCRYPTION_KEY" "$SOCKS_PORT"
else
    error "Не найден исполняемый файл клиента!"
    error "Проверьте структуру $OLCRTC_DIR"
    ls -la "$OLCRTC_DIR/"
    exit 1
fi
