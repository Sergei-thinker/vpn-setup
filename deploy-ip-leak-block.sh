#!/bin/bash
# =============================================================================
# deploy-ip-leak-block.sh — применить IP-leak blocklist в 3X-UI xray template
# =============================================================================
# Вставляет в x-ui.db настройку `xrayTemplateConfig` с routing-правилом,
# которое блокирует 17 IP-leak эндпоинтов (api.ipify.org, ifconfig.me,
# icanhazip.com, 2ip.*, redirector.googlevideo.com и т. д.).
#
# Idempotent: если template уже содержит block-правило с маркером,
# повторный запуск не дублирует.
#
# Usage: python ssh_exec.py deploy deploy-ip-leak-block.sh
# =============================================================================

set -euo pipefail

XUI_DB="/etc/x-ui/x-ui.db"
RUNTIME_CFG="/usr/local/x-ui/bin/config.json"
MARKER="ip-leak-block-rule-v1"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
ok()   { echo "${GREEN}[OK]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
fail() { echo "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root"
[[ -f "$XUI_DB" ]] || fail "x-ui.db not found at $XUI_DB"
[[ -f "$RUNTIME_CFG" ]] || fail "runtime config not found at $RUNTIME_CFG"

# Проверка что jq / python3 доступны
command -v python3 >/dev/null || fail "python3 required"

# Проверка идемпотентности
if sqlite3 "$XUI_DB" "SELECT value FROM settings WHERE key='xrayTemplateConfig';" 2>/dev/null | grep -q "$MARKER"; then
    ok "IP-leak block rule уже установлен (marker: $MARKER)"
    # Но всё равно рестартуем, если runtime config не синхронизирован
    if ! grep -q "ipify.org" "$RUNTIME_CFG"; then
        warn "Marker есть в DB, но runtime config устарел — перезапускаю x-ui"
        systemctl restart x-ui
        sleep 3
    else
        ok "Runtime config содержит правило — ничего не делаю"
        exit 0
    fi
fi

echo "Применение IP-leak block rule..."

# Читаем текущий runtime config и формируем template
python3 <<'PYEOF'
import json, sqlite3, os, sys

RUNTIME_CFG = "/usr/local/x-ui/bin/config.json"
XUI_DB = "/etc/x-ui/x-ui.db"
MARKER = "ip-leak-block-rule-v1"

with open(RUNTIME_CFG) as f:
    cfg = json.load(f)

# 3X-UI template = конфиг без inbounds (inbounds мёрджатся из DB в runtime)
template = {k: v for k, v in cfg.items() if k != "inbounds"}

# IP-leak block rule
leak_rule = {
    "type": "field",
    "outboundTag": "blocked",
    "domain": [
        "domain:ipify.org",
        "domain:ifconfig.me",
        "domain:ifconfig.io",
        "domain:ifconfig.co",
        "domain:icanhazip.com",
        "domain:ipinfo.io",
        "domain:ipapi.co",
        "domain:ip-api.com",
        "domain:checkip.amazonaws.com",
        "domain:checkip.dyndns.com",
        "domain:wtfismyip.com",
        "domain:my-ip.io",
        "domain:myexternalip.com",
        "domain:ipecho.net",
        "domain:2ip.io",
        "domain:2ip.ru",
        "full:redirector.googlevideo.com"
    ],
    "_comment": f"anti-deanon IP-leak blocklist ({MARKER}); source: habr 1021160 + 1023224"
}

# Удаляем старые rule с нашим маркером (если были) и добавляем свежий
rules = template.setdefault("routing", {}).setdefault("rules", [])
rules = [r for r in rules if r.get("_comment", "").find(MARKER) == -1]
# Вставляем правило ПОСЛЕ api-rule и ДО других блок-правил — чем раньше, тем раньше срабатывает
api_idx = next((i for i, r in enumerate(rules) if r.get("outboundTag") == "api"), -1)
insert_at = api_idx + 1 if api_idx != -1 else 0
rules.insert(insert_at, leak_rule)
template["routing"]["rules"] = rules

# Сохраняем как xrayTemplateConfig в settings DB
tmpl_json = json.dumps(template, ensure_ascii=False, indent=2)

conn = sqlite3.connect(XUI_DB)
cur = conn.cursor()
existing = cur.execute("SELECT id FROM settings WHERE key=?", ("xrayTemplateConfig",)).fetchone()
if existing:
    cur.execute("UPDATE settings SET value=? WHERE key=?", (tmpl_json, "xrayTemplateConfig"))
    print(f"[OK] xrayTemplateConfig updated (id={existing[0]}, size={len(tmpl_json)} bytes)")
else:
    cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", ("xrayTemplateConfig", tmpl_json))
    print(f"[OK] xrayTemplateConfig inserted (size={len(tmpl_json)} bytes)")
conn.commit()
conn.close()

# Бэкап template для инспекции
with open("/root/xray-template-with-leak-block.json", "w") as f:
    f.write(tmpl_json)
print("[OK] template saved to /root/xray-template-with-leak-block.json")
PYEOF

echo "Перезапуск x-ui для применения template..."
systemctl restart x-ui
sleep 3

# Верификация: runtime config должен содержать наш block-домен
if grep -q "ipify.org" "$RUNTIME_CFG" 2>/dev/null; then
    ok "Runtime config обновлён, ipify.org присутствует в routing"
else
    fail "Runtime config НЕ содержит ipify.org после рестарта — template не применился"
fi

# Финальная проверка статуса
if systemctl is-active x-ui >/dev/null; then
    ok "x-ui: active"
else
    fail "x-ui не запустился — откатите template через 3X-UI Panel → Xray Settings"
fi

echo ""
echo "Проверка routing в runtime config:"
python3 -c "
import json
c = json.load(open('$RUNTIME_CFG'))
for i, r in enumerate(c['routing']['rules']):
    tag = r.get('outboundTag', '?')
    doms = r.get('domain', [])
    ips = r.get('ip', [])
    note = ''
    if any('ipify' in d for d in doms):
        note = ' ← IP-leak block rule'
    print(f'  rule[{i}]: -> {tag}  ({len(doms)} domains, {len(ips)} ip ranges){note}')
"
