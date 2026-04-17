#!/bin/bash
# =============================================================================
# test-leak-block.sh — функциональный тест серверного IP-leak blocklist
# =============================================================================
# На VPS поднимает xray в клиентском режиме (socks5 localhost:10808),
# outbound — VLESS Reality на свой же inbound 443. Затем через этот
# socks5 пытается достучаться до api.ipify.org и контрольного google.
# ipify должен упасть (блок сработал), google — ответить.
# =============================================================================
set -u

XUI_DB="/etc/x-ui/x-ui.db"
CFG_FILE="/tmp/xray-leak-test-client.json"
LOG_FILE="/tmp/xray-leak-test.log"
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"

# Вытаскиваем UUID + public key из DB одним python-скриптом
eval "$(python3 <<PYEOF
import sqlite3, json, subprocess
conn = sqlite3.connect("$XUI_DB")
row = conn.execute("SELECT settings, stream_settings FROM inbounds WHERE port=443 LIMIT 1").fetchone()
conn.close()
s = json.loads(row[0]); ss = json.loads(row[1])
uid = s["clients"][0]["id"]
priv = ss["realitySettings"]["privateKey"]
sid = ss["realitySettings"]["shortIds"][0]
sni = ss["realitySettings"]["serverNames"][0]
out = subprocess.run(["$XRAY_BIN", "x25519", "-i", priv], capture_output=True, text=True).stdout
pub = ""
for line in out.splitlines():
    if "Password" in line or "Public key" in line:
        pub = line.split(":",1)[1].strip()
        break
print(f"UUID={uid!r}")
print(f"PRIV_KEY={priv!r}")
print(f"SID={sid!r}")
print(f"SNI={sni!r}")
print(f"PUB_KEY={pub!r}")
PYEOF
)"

echo "UUID=$UUID"
echo "SNI=$SNI"
echo "SID=$SID"
echo "PUB_KEY=$PUB_KEY"

cat > "$CFG_FILE" <<EOF
{
  "log": {"loglevel": "warning", "access": "$LOG_FILE"},
  "inbounds": [{
    "tag": "socks-in",
    "port": 10808,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {"auth": "noauth", "udp": false}
  }],
  "outbounds": [{
    "tag": "reality-out",
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "127.0.0.1",
        "port": 443,
        "users": [{"id": "$UUID", "encryption": "none", "flow": ""}]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "$SNI",
        "fingerprint": "chrome",
        "publicKey": "$PUB_KEY",
        "shortId": "$SID",
        "spiderX": "/"
      }
    }
  }]
}
EOF

# Запускаем клиент в фоне
"$XRAY_BIN" run -c "$CFG_FILE" > /tmp/xray-client.stderr 2>&1 &
CLIENT_PID=$!
sleep 2

if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
    echo "ERROR: xray client не запустился. stderr:"
    cat /tmp/xray-client.stderr
    exit 1
fi

echo ""
echo "=== Тест: запрос через socks5 к api.ipify.org (должен БЛОК) ==="
if timeout 10 curl -sS -o /dev/null -w "HTTP %{http_code}, curl exit %{exitcode}" --socks5-hostname 127.0.0.1:10808 https://api.ipify.org 2>&1; then
    RESULT_IPIFY="reachable (LEAK!)"
else
    RESULT_IPIFY="blocked (✓)"
fi
echo ""
echo "=== Контроль: запрос к google.com/generate_204 (должен ответить) ==="
if timeout 10 curl -sS -o /dev/null -w "HTTP %{http_code}" --socks5-hostname 127.0.0.1:10808 https://www.google.com/generate_204 2>&1; then
    RESULT_GOOGLE="reachable (✓)"
else
    RESULT_GOOGLE="blocked (ошибка конфига?)"
fi

echo ""
echo "=== Результат ==="
echo "  api.ipify.org: $RESULT_IPIFY"
echo "  google:        $RESULT_GOOGLE"
echo ""
echo "=== Последние строки log клиента ==="
tail -20 "$LOG_FILE" 2>/dev/null || true

# Cleanup
kill "$CLIENT_PID" 2>/dev/null || true
rm -f "$CFG_FILE" /tmp/xray-client.stderr
