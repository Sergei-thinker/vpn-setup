#!/bin/bash
# =============================================================================
# check-ip-leaks.sh — верификация блока IP-leak эндпоинтов
# =============================================================================
# После применения client-configs/xray-server-routing.json + клиентских
# блок-листов дёргает каждый leak-домен и убеждается, что ответ = блок/timeout,
# а не валидный IP.
#
# Запускать С КЛИЕНТА (через активный VPN), не с сервера.
#
# Usage:
#   bash check-ip-leaks.sh               # запрос напрямую через текущий системный прокси/TUN
#   bash check-ip-leaks.sh --proxy socks5h://127.0.0.1:10808   # через конкретный прокси
#   bash check-ip-leaks.sh --timeout 5    # custom timeout (по умолчанию 8s)
#
# Exit code: 0 = все leak-эндпоинты заблокированы; >0 = N утечек найдено.
# =============================================================================

set -u

PROXY=""
TIMEOUT=8

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy) PROXY="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Leak-домены: те же, что в client-configs/xray-server-routing.json (block rule).
LEAK_ENDPOINTS=(
    "https://api.ipify.org?format=text"
    "https://api4.ipify.org"
    "https://api6.ipify.org"
    "https://ifconfig.me/ip"
    "https://ifconfig.io/ip"
    "https://ifconfig.co/ip"
    "https://icanhazip.com"
    "https://ipinfo.io/ip"
    "https://ipapi.co/ip"
    "http://ip-api.com/line?fields=query"
    "https://checkip.amazonaws.com"
    "https://checkip.dyndns.com"
    "https://wtfismyip.com/text"
    "https://api.my-ip.io/ip"
    "https://myexternalip.com/raw"
    "https://ipecho.net/plain"
    "https://api.2ip.io/ip.json"
    "https://2ip.ru"
)

# Контрольные домены: должны работать нормально (НЕ заблокированы)
CONTROL_ENDPOINTS=(
    "https://www.google.com/generate_204"  # 204 No Content — быстрая проверка
    "https://cloudflare.com/cdn-cgi/trace"
)

BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

CURL_OPTS=(-s -o /dev/null -w "%{http_code} %{time_total}" --max-time "$TIMEOUT" --connect-timeout 5)
if [[ -n "$PROXY" ]]; then
    CURL_OPTS+=(--proxy "$PROXY")
fi

echo "${BOLD}Проверка блока IP-leak эндпоинтов${NC}"
[[ -n "$PROXY" ]] && echo "Proxy: $PROXY"
echo "Timeout: ${TIMEOUT}s"
echo ""

LEAKS=0
TOTAL=${#LEAK_ENDPOINTS[@]}

for url in "${LEAK_ENDPOINTS[@]}"; do
    result=$(curl "${CURL_OPTS[@]}" "$url" 2>&1 || echo "000 timeout")
    http_code=$(echo "$result" | awk '{print $1}')

    # Блок ожидаем как: connection refused / timeout (curl code 7, 28 → http_code=000)
    # ИЛИ любой не-2xx. 2xx = утечка (endpoint успешно ответил).
    if [[ "$http_code" =~ ^2 ]]; then
        # Endpoint успешно ответил — УТЕЧКА. Проверим, что возвращает, но без загрузки большого тела.
        body=$(curl -s --max-time "$TIMEOUT" ${PROXY:+--proxy "$PROXY"} "$url" 2>/dev/null | head -c 64 | tr -d '\r\n' || echo "")
        printf "  ${RED}[LEAK]${NC} %-50s → %s (IP leaked: %s)\n" "$url" "$http_code" "$body"
        LEAKS=$((LEAKS + 1))
    else
        printf "  ${GREEN}[BLOCK]${NC} %-50s → %s\n" "$url" "$http_code"
    fi
done

echo ""
echo "${BOLD}Контрольные эндпоинты (должны отвечать):${NC}"
CONTROL_FAILS=0
for url in "${CONTROL_ENDPOINTS[@]}"; do
    result=$(curl "${CURL_OPTS[@]}" "$url" 2>&1 || echo "000 timeout")
    http_code=$(echo "$result" | awk '{print $1}')
    if [[ "$http_code" =~ ^[23] ]]; then
        printf "  ${GREEN}[OK]${NC}    %-50s → %s\n" "$url" "$http_code"
    else
        printf "  ${YELLOW}[UNREACHABLE]${NC} %-50s → %s (VPN вообще работает?)\n" "$url" "$http_code"
        CONTROL_FAILS=$((CONTROL_FAILS + 1))
    fi
done

echo ""
if (( LEAKS == 0 )); then
    echo "${GREEN}${BOLD}OK${NC}: все $TOTAL leak-эндпоинтов заблокированы."
    if (( CONTROL_FAILS > 0 )); then
        echo "${YELLOW}Но${NC}: $CONTROL_FAILS контрольных эндпоинтов недоступны. Проверьте VPN."
        exit 3
    fi
    exit 0
else
    echo "${RED}${BOLD}LEAK${NC}: $LEAKS из $TOTAL leak-эндпоинтов пропустили запрос."
    echo "Причины:"
    echo "  1. Конфиг xray-server-routing.json не применён на сервере (3X-UI Panel → Xray Settings → Routing)."
    echo "  2. Клиент использует прямое подключение (проверьте: что такое 'активный VPN')."
    echo "  3. Клиент не подхватил обновлённый routing (перезапустите клиент)."
    exit 1
fi
