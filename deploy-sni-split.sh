#!/bin/bash
# =============================================================================
# Layer 0.5: nginx ssl_preread SNI-split + LE + basic_auth stub
# =============================================================================
# Ставит nginx перед xray. На 443 — nginx stream с ssl_preread. Трафик
# с SNI=xk127r.top уходит на локальную HTTPS-заглушку "Portfolio / Coming Soon"
# с basic_auth. Остальные SNI (microsoft/google/apple и их ротации) проксятся
# в xray на loopback-порты 10443/10444/10453. Реальный Reality-трафик
# остаётся неизменным — nginx ssl_preread не расшифровывает TLS.
#
# Источник рецепта: @ice938 в комментах к habr.com/ru/articles/1021160
#
# Usage: python ssh_exec.py deploy deploy-sni-split.sh
#        или: scp deploy-sni-split.sh root@VPS:/root/ && ssh root@VPS 'bash /root/deploy-sni-split.sh'
#
# Требуется заранее:
#   - A-запись xk127r.top → IP VPS (без Cloudflare Proxy, иначе LE не выпустится)
#   - Порт 80 открыт для ACME challenge
#   - Активная 3X-UI инсталляция с Reality inbound на 443
#
# Идемпотентен: повторный запуск не ломает установку, обновляет только
# изменившиеся секции.
# =============================================================================

set -euo pipefail

# --------- Config ---------
STUB_DOMAIN="${STUB_DOMAIN:-xk127r.top}"
STUB_EMAIL="${STUB_EMAIL:-admin@${STUB_DOMAIN}}"
STUB_USER="${STUB_USER:-admin}"
# STUB_PASS: если не задан, генерируется случайный и пишется в /root/stub-credentials.txt
STUB_PASS="${STUB_PASS:-}"

# Порты, на которые nginx будет проксировать xray (loopback)
XRAY_MAIN_PORT=10443       # был 443 (reality-main, microsoft/bing/azure)
XRAY_GOOGLE_PORT=10444     # был 8443 (reality-google)
XRAY_APPLE_PORT=10453      # был 2053 (reality-apple)

XUI_DB="/etc/x-ui/x-ui.db"
STUB_ROOT="/var/www/${STUB_DOMAIN}"
NGINX_STREAM_CONF="/etc/nginx/conf.d/sni-split.conf"
NGINX_HTTPS_CONF="/etc/nginx/sites-available/${STUB_DOMAIN}.conf"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled/${STUB_DOMAIN}.conf"
CREDS_FILE="/root/stub-credentials.txt"

# --------- Helpers ---------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}[$1/8] $2${NC}"; }

[[ $EUID -eq 0 ]] || fail "Run as root"

echo -e "${BOLD}"
echo "============================================================"
echo "  Layer 0.5 — nginx SNI-split deploy"
echo "  Domain: ${STUB_DOMAIN}"
echo "============================================================"
echo -e "${NC}"

# =============================================================================
# 1. Проверка предусловий
# =============================================================================
step 1 "Проверка предусловий"

# DNS resolution
IP_OF_DOMAIN=$(dig +short "$STUB_DOMAIN" @1.1.1.1 | tail -n1 || true)
IP_OF_HOST=$(curl -s https://api4.ipify.org || curl -s https://ifconfig.me || echo "")
# NB: ipify тут используется для self-check сервера, не клиента. На сервере leak-block не активен.

if [[ -z "$IP_OF_DOMAIN" ]]; then
    fail "A-запись ${STUB_DOMAIN} не резолвится. Проверьте DNS (A-запись на IP VPS, БЕЗ Cloudflare Proxy)."
fi
if [[ -n "$IP_OF_HOST" && "$IP_OF_DOMAIN" != "$IP_OF_HOST" ]]; then
    warn "${STUB_DOMAIN} резолвится в ${IP_OF_DOMAIN}, но сервер имеет ${IP_OF_HOST}. Проверьте, что Cloudflare Proxy выключен."
fi
ok "DNS: ${STUB_DOMAIN} → ${IP_OF_DOMAIN}"

# x-ui presence
systemctl is-active x-ui >/dev/null 2>&1 || warn "x-ui не запущен. Layer 0.5 всё равно установится, но проверьте x-ui после деплоя."
[[ -f "$XUI_DB" ]] || warn "x-ui DB не найдена (${XUI_DB}). Inbound-ы не будут переключены на loopback, это нужно сделать вручную."

# =============================================================================
# 2. Установка nginx + certbot
# =============================================================================
step 2 "Установка nginx + certbot"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx apache2-utils dnsutils >/dev/null
ok "nginx $(nginx -v 2>&1 | awk -F/ '{print $2}')"
ok "certbot $(certbot --version 2>&1 | awk '{print $2}')"

# Nginx stream module: в Debian 12 stream подгружается из /etc/nginx/modules-enabled/
# Ubuntu/Debian пакет nginx уже включает stream module статически
nginx -V 2>&1 | grep -q with-stream || fail "nginx собран без --with-stream. Поставьте nginx-full."
ok "nginx stream module доступен"

# =============================================================================
# 3. Stub site (HTTP, для LE challenge)
# =============================================================================
step 3 "Static stub + Let's Encrypt"

mkdir -p "$STUB_ROOT"
cat > "$STUB_ROOT/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Portfolio — Coming Soon</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         background: #0f0f10; color: #e5e5e5; margin: 0;
         display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .box { text-align: center; padding: 2rem; }
  h1 { font-weight: 300; letter-spacing: 1px; margin: 0 0 0.5rem; }
  p { color: #888; margin: 0; }
</style>
</head>
<body>
  <div class="box">
    <h1>Coming Soon</h1>
    <p>Portfolio site under construction.</p>
  </div>
</body>
</html>
HTML

chown -R www-data:www-data "$STUB_ROOT"
chmod 755 "$STUB_ROOT"

# basic_auth
if [[ -z "$STUB_PASS" ]]; then
    STUB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    echo "Generated basic_auth password: ${STUB_USER} / ${STUB_PASS}"
fi
htpasswd -bc /etc/nginx/.htpasswd-stub "$STUB_USER" "$STUB_PASS" >/dev/null
chmod 640 /etc/nginx/.htpasswd-stub
chown root:www-data /etc/nginx/.htpasswd-stub
ok "stub: ${STUB_ROOT} + basic_auth (${STUB_USER})"

# Временный HTTP-конфиг для certbot
cat > /etc/nginx/sites-available/${STUB_DOMAIN}-acme.conf <<NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${STUB_DOMAIN} www.${STUB_DOMAIN};
    root ${STUB_ROOT};
    location /.well-known/acme-challenge/ { allow all; }
    location / { return 200 'ok'; add_header Content-Type text/plain; }
}
NGINXCONF
ln -sf /etc/nginx/sites-available/${STUB_DOMAIN}-acme.conf /etc/nginx/sites-enabled/${STUB_DOMAIN}-acme.conf
nginx -t >/dev/null 2>&1 || fail "nginx -t failed после HTTP-конфига"
systemctl reload nginx

# Запрос сертификата (idempotent: certbot --keep сохранит если уже есть)
if [[ ! -d "/etc/letsencrypt/live/${STUB_DOMAIN}" ]]; then
    certbot certonly --nginx -n --agree-tos --email "$STUB_EMAIL" \
        -d "$STUB_DOMAIN" -d "www.${STUB_DOMAIN}" --keep-until-expiring \
        || fail "certbot не смог выпустить сертификат"
    ok "LE сертификат выпущен"
else
    ok "LE сертификат уже существует, пропускаю"
fi

# =============================================================================
# 4. HTTPS-vhost заглушки (слушает 127.0.0.1:10080)
# =============================================================================
step 4 "HTTPS-заглушка на 127.0.0.1:10080"

cat > "$NGINX_HTTPS_CONF" <<NGINXCONF
server {
    listen 127.0.0.1:10080 ssl http2;
    server_name ${STUB_DOMAIN} www.${STUB_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${STUB_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${STUB_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    root ${STUB_ROOT};
    index index.html;

    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd-stub;

    location / { try_files \$uri \$uri/ =404; }
    location /.well-known/acme-challenge/ { auth_basic off; allow all; }
}

# HTTP→HTTPS для LE renewal и для легитимных визитов
server {
    listen 80;
    listen [::]:80;
    server_name ${STUB_DOMAIN} www.${STUB_DOMAIN};
    root ${STUB_ROOT};
    location /.well-known/acme-challenge/ { allow all; }
    location / { return 301 https://\$host\$request_uri; }
}
NGINXCONF
ln -sf "$NGINX_HTTPS_CONF" "$NGINX_SITES_ENABLED"
rm -f /etc/nginx/sites-enabled/${STUB_DOMAIN}-acme.conf  # cleanup acme-only config

# Скрываем default vhost
rm -f /etc/nginx/sites-enabled/default

nginx -t >/dev/null 2>&1 || fail "nginx -t failed после HTTPS-конфига"
ok "HTTPS-vhost на 127.0.0.1:10080"

# =============================================================================
# 5. Переключение xray inbound на loopback
# =============================================================================
step 5 "Перенос Reality inbound на 127.0.0.1:10443/10444/10453"

if [[ -f "$XUI_DB" ]]; then
    # SQL: найти reality-* inbound и поменять listen + port
    # ВАЖНО: сохраняем клиентские ссылки живыми — VLESS URL ссылается на внешний порт 443,
    # туда nginx и слушает → клиенту ничего менять не нужно.
    sqlite3 "$XUI_DB" <<SQL
UPDATE inbounds SET listen='127.0.0.1', port=${XRAY_MAIN_PORT}   WHERE tag='inbound-443';
UPDATE inbounds SET listen='127.0.0.1', port=${XRAY_GOOGLE_PORT} WHERE tag='inbound-8443';
UPDATE inbounds SET listen='127.0.0.1', port=${XRAY_APPLE_PORT}  WHERE tag='inbound-2053';
SQL
    systemctl restart x-ui
    sleep 2
    systemctl is-active x-ui >/dev/null && ok "x-ui перезапущен" || warn "x-ui не активен после рестарта — проверьте логи"
else
    warn "x-ui DB отсутствует — пропускаю. Вручную переведите Reality inbound на 127.0.0.1:${XRAY_MAIN_PORT}/${XRAY_GOOGLE_PORT}/${XRAY_APPLE_PORT}"
fi

# =============================================================================
# 6. nginx stream SNI-split на 0.0.0.0:443
# =============================================================================
step 6 "nginx stream SNI-split (ssl_preread)"

# Debian/Ubuntu: stream-секция включается в /etc/nginx/nginx.conf — уже добавлена пакетом.
# Проверим и при необходимости добавим include для conf.d.
if ! grep -q "^stream {" /etc/nginx/nginx.conf; then
    cat >> /etc/nginx/nginx.conf <<'NGINXCONF'

stream {
    include /etc/nginx/conf.d/*.stream;
}
NGINXCONF
    warn "Добавлена stream {} секция в /etc/nginx/nginx.conf"
fi

# Файл .stream вместо .conf (stream read только .stream по маске выше),
# чтобы не конфликтовать с http-блоками в conf.d.
cat > "${NGINX_STREAM_CONF%.conf}.stream" <<NGINXCONF
# SNI-split: маршрутизация TCP на backend по SNI из ClientHello без расшифровки TLS
# Источник: @ice938 (habr.com/ru/articles/1021160 comments)

map \$ssl_preread_server_name \$sni_backend {
    # Наш домен → static-заглушка
    ${STUB_DOMAIN}                127.0.0.1:10080;
    www.${STUB_DOMAIN}            127.0.0.1:10080;

    # Reality (microsoft/bing/azure pool)
    www.microsoft.com             127.0.0.1:${XRAY_MAIN_PORT};
    microsoft.com                 127.0.0.1:${XRAY_MAIN_PORT};
    www.bing.com                  127.0.0.1:${XRAY_MAIN_PORT};
    azure.microsoft.com           127.0.0.1:${XRAY_MAIN_PORT};

    # Reality (google pool)
    dl.google.com                 127.0.0.1:${XRAY_GOOGLE_PORT};
    www.google.com                127.0.0.1:${XRAY_GOOGLE_PORT};
    accounts.google.com           127.0.0.1:${XRAY_GOOGLE_PORT};
    mail.google.com               127.0.0.1:${XRAY_GOOGLE_PORT};

    # Reality (apple pool)
    www.apple.com                 127.0.0.1:${XRAY_APPLE_PORT};
    apple.com                     127.0.0.1:${XRAY_APPLE_PORT};
    www.icloud.com                127.0.0.1:${XRAY_APPLE_PORT};
    support.apple.com             127.0.0.1:${XRAY_APPLE_PORT};

    # Неизвестный SNI → заглушка (а не xray — не палим Reality на перебор)
    default                       127.0.0.1:10080;
}

server {
    listen 443 reuseport;
    listen [::]:443 reuseport;
    ssl_preread on;
    proxy_pass \$sni_backend;
    proxy_connect_timeout 5s;

    # Long-lived Reality connections
    proxy_timeout 10m;
}
NGINXCONF
ok "stream config: ${NGINX_STREAM_CONF%.conf}.stream"

nginx -t >/dev/null 2>&1 || fail "nginx -t failed после stream-конфига"
systemctl reload nginx
sleep 1
systemctl is-active nginx >/dev/null && ok "nginx активен" || fail "nginx не запустился"

# =============================================================================
# 7. LE auto-renewal hook для nginx-reload
# =============================================================================
step 7 "LE auto-renewal"

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/bash
systemctl reload nginx
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
ok "LE auto-renewal: nginx reload after cert update"

# =============================================================================
# 8. Сохранение credentials + финальный вывод
# =============================================================================
step 8 "Результаты"

cat > "$CREDS_FILE" <<CREDS
# ============================================================
# Layer 0.5 — SNI-split deploy credentials
# Generated: $(date -Is)
# ============================================================

Stub domain:       https://${STUB_DOMAIN}/
Basic auth user:   ${STUB_USER}
Basic auth pass:   ${STUB_PASS}

Reality backend ports (loopback):
  reality-main (microsoft): 127.0.0.1:${XRAY_MAIN_PORT}
  reality-google:           127.0.0.1:${XRAY_GOOGLE_PORT}
  reality-apple:            127.0.0.1:${XRAY_APPLE_PORT}

Client VLESS URLs остались без изменений (внешний порт 443, nginx проксирует в xray).

Откат: bash deploy-sni-split.sh --rollback  (не реализовано; сделайте:
  - systemctl disable nginx; systemctl stop nginx
  - sqlite3 ${XUI_DB} "UPDATE inbounds SET listen='', port=443 WHERE tag='inbound-443'; UPDATE inbounds SET listen='', port=8443 WHERE tag='inbound-8443'; UPDATE inbounds SET listen='', port=2053 WHERE tag='inbound-2053';"
  - systemctl restart x-ui
)
CREDS
chmod 600 "$CREDS_FILE"

echo ""
echo -e "${BOLD}${GREEN}Layer 0.5 установлен.${NC}"
echo -e "  ${BOLD}Stub:${NC}   https://${STUB_DOMAIN}/ (basic_auth: ${STUB_USER} / ${STUB_PASS})"
echo -e "  ${BOLD}Creds:${NC}  ${CREDS_FILE}"
echo ""
echo "Тест:"
echo "  curl -v -u ${STUB_USER}:${STUB_PASS} https://${STUB_DOMAIN}/    # заглушка"
echo "  openssl s_client -connect ${IP_OF_HOST:-<IP>}:443 -servername www.microsoft.com -brief  # Reality"
echo ""
