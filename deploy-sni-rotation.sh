#!/bin/bash
# =============================================================================
# deploy-sni-rotation.sh — расширить serverNames существующих Reality inbounds
# =============================================================================
# Изменение ПО ДОБАВЛЕНИЮ: исходные SNI клиентов остаются в списке,
# клиентские ссылки продолжают работать. DPI видит больше вариаций.
#
# inbound port 443 (microsoft): +www.bing.com, +azure.microsoft.com
# inbound port 8443 (google):   +www.google.com, +accounts.google.com, +mail.google.com
# inbound port 2053 (apple):    +www.icloud.com, +support.apple.com
#
# Idempotent: повторный запуск не ломает.
# Usage: python ssh_exec.py deploy deploy-sni-rotation.sh
# =============================================================================
set -euo pipefail

XUI_DB="/etc/x-ui/x-ui.db"
RUNTIME_CFG="/usr/local/x-ui/bin/config.json"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
fail() { echo "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root"
[[ -f "$XUI_DB" ]] || fail "x-ui.db not found"

python3 <<'PYEOF'
import sqlite3, json

XUI_DB = "/etc/x-ui/x-ui.db"

POOLS = {
    443:  ["www.microsoft.com", "microsoft.com", "www.bing.com", "azure.microsoft.com"],
    8443: ["dl.google.com", "www.google.com", "accounts.google.com", "mail.google.com"],
    2053: ["www.apple.com", "apple.com", "www.icloud.com", "support.apple.com"],
}

conn = sqlite3.connect(XUI_DB)
cur = conn.cursor()

updated = 0
for port, pool in POOLS.items():
    row = cur.execute("SELECT id, stream_settings FROM inbounds WHERE port=?", (port,)).fetchone()
    if not row:
        print(f"[WARN] inbound port={port} не найден, пропускаю")
        continue
    inbound_id, ss_raw = row
    ss = json.loads(ss_raw)
    reality = ss.get("realitySettings")
    if not reality:
        print(f"[WARN] inbound port={port} без realitySettings, пропускаю")
        continue
    current = reality.get("serverNames", [])
    # Объединяем текущие + пул, без дублей, сохраняя порядок (существующие первыми)
    merged = list(current)
    for sn in pool:
        if sn not in merged:
            merged.append(sn)
    if merged == current:
        print(f"[OK] inbound port={port} уже имеет {len(current)} SNI — без изменений")
        continue
    reality["serverNames"] = merged
    ss["realitySettings"] = reality
    cur.execute("UPDATE inbounds SET stream_settings=? WHERE id=?", (json.dumps(ss), inbound_id))
    print(f"[OK] inbound port={port}: {len(current)} → {len(merged)} SNI: {merged}")
    updated += 1

conn.commit()
conn.close()
print(f"\n[SUMMARY] Обновлено inbounds: {updated}")
PYEOF

if [ $? -ne 0 ]; then
    fail "Python DB update failed"
fi

echo ""
echo "Перезапуск x-ui для применения новых SNI..."
systemctl restart x-ui
sleep 3

# Верификация
python3 <<PYEOF
import json
c = json.load(open("$RUNTIME_CFG"))
print("Runtime config — Reality inbounds:")
for ib in c.get("inbounds", []):
    ss = ib.get("streamSettings") or {}
    rs = ss.get("realitySettings") or {}
    sns = rs.get("serverNames", [])
    if sns:
        print(f"  port {ib['port']}: {sns}")
PYEOF

systemctl is-active x-ui >/dev/null && ok "x-ui active" || fail "x-ui не запустился"
