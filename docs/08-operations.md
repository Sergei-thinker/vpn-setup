# 8. Обслуживание и мониторинг

## Автоматический мониторинг Xray

Скрипт `/root/monitor-xray.sh` проверяет процесс каждые 5 минут:
```bash
#!/bin/bash
if ! pgrep -x xray > /dev/null; then
    x-ui restart
    echo "$(date): Xray restarted" >> /var/log/xray-monitor.log
fi
```
Cron: `*/5 * * * * /root/monitor-xray.sh`

## Внешний мониторинг
- **UptimeRobot** (бесплатно, 5 мин) — мониторинг порта 443
- Telegram-бот для алертов (BetterStack / Healthchecks.io)

## Регулярные действия

| Действие | Частота | Команда |
|----------|---------|---------|
| Обновить Xray-core | 1 раз/мес | Панель -> Overview -> Xray -> Update |
| Обновить 3X-UI | По мере выхода | `x-ui update` |
| Обновить ОС | 1 раз/мес | `apt update && apt upgrade -y` |
| Обновить geosite/geoip | 1 раз/мес | `wget -O .../geosite.dat ...` |
| Проверить SSL | Автоматически | Let's Encrypt auto-renew |
| Проверить логи | При проблемах | `x-ui log` или `python ssh_exec.py logs` |

## Если VPN перестал работать

**Алгоритм действий:**
1. Проверить сервер: `python ssh_exec.py status`
2. Перезапустить: `python ssh_exec.py restart`
3. Проверить логи: `python ssh_exec.py logs`
4. Если основной порт заблокирован -> переключиться на backup inbound (8443 или 2053)
5. Если IP заблокирован целиком -> переключиться на relay через Yandex Cloud (Layer 1)
6. Если relay недоступен -> попробовать WebRTC через Телемост (Layer 2)
7. На домашнем Wi-Fi -> попробовать Cloudflare CDN (Layer 3, блокируется ТСПУ с 2025)
8. **Крайний случай:** пересоздать сервер (`quick-rebuild.sh`)

## Управление через ssh_exec.py

```bash
python ssh_exec.py status      # Статус xray, uptime, соединения
python ssh_exec.py restart     # Перезапуск x-ui/xray
python ssh_exec.py logs        # Последние логи
python ssh_exec.py exec "cmd"  # Произвольная команда
python ssh_exec.py deploy script.sh  # Загрузить и выполнить скрипт
python ssh_exec.py backup      # Скачать бэкап x-ui.db
```

---

## Relay VPS (Layer 1) — Управление

Relay VPS управляется через `ssh_exec.py` с флагом `-t relay`:

```bash
python ssh_exec.py -t relay status    # Статус relay VPS (xray, uptime, соединения)
python ssh_exec.py -t relay logs      # Последние логи Xray на relay
python ssh_exec.py -t relay restart   # Перезапуск xray на relay
python ssh_exec.py relay-status       # Статус обоих VPS одновременно (Швеция + РФ)
bash monitor-relay.sh                 # Health check обоих VPS (проверка доступности портов)
```

**Деплой relay:**
```bash
# 1. Подготовить шведский VPS (создать принимающий inbound)
python ssh_exec.py deploy deploy-relay-sweden.sh

# 2. Развернуть relay на российском VPS
python ssh_exec.py -t relay deploy deploy-relay.sh
```

**Если relay не работает:**
1. `python ssh_exec.py -t relay status` — проверить что xray запущен
2. `python ssh_exec.py -t relay logs` — посмотреть ошибки
3. Проверить что шведский VPS принимает соединения на порту 10443
4. `python ssh_exec.py -t relay restart` — перезапустить relay

---

## Быстрое восстановление (Disaster Recovery)

### Сценарий
IP заблокирован, сервер нужно пересоздать с нуля.

### Порядок действий (30 минут)

1. **Удалить старый сервер** у провайдера
2. **Создать новый** (любой EU KVM VPS с Debian 12)
3. **Скопировать и запустить quick-rebuild.sh:**
```bash
scp quick-rebuild.sh root@NEW_IP:/root/
ssh root@NEW_IP "bash /root/quick-rebuild.sh"
```
4. Скрипт автоматически:
   - Установит 3X-UI + Xray
   - Создаст все inbound-ы (443, 8443, 2053, 2082)
   - Применит BBR, DNS, UFW, fail2ban
   - Настроит Nginx-камуфляж
   - Установит мониторинг
   - Выведет все credentials и VLESS-ссылки

5. **Обновить Cloudflare DNS** A-запись -> новый IP
6. **Обновить subscription** в клиентах (или импортировать новые ссылки)

### Файлы проекта

| Файл | Назначение |
|------|-----------|
| `quick-rebuild.sh` | Полная установка с нуля |
| `deploy-multilayer.sh` | Добавление multi-layer к существующему серверу |
| `optimize-server.sh` | Базовая оптимизация (legacy) |
| `ssh_exec.py` | SSH-утилита управления |
| `deploy-relay-sweden.sh` | Создание xHTTP inbound на шведском VPS |
| `deploy-relay.sh` | Полный деплой relay на российском VPS |
| `monitor-relay.sh` | Health check обоих VPS |
| `cloudflare-worker/` | Cloudflare Worker для CDN-фронтинга |
| `client-configs/` | Конфиги split routing для всех платформ |

---

## Быстрая диагностика

| Проблема | Диагностика | Решение |
|----------|-------------|---------|
| VPN не подключается | `python ssh_exec.py status` | Проверить что xray запущен, перезапустить: `python ssh_exec.py restart` |
| Подключается, но нет интернета | Проверить routing в клиенте | Убедиться что split routing настроен правильно |
| Работает Wi-Fi, не работает LTE | Мобильный оператор блокирует агрессивнее | TLS-фрагментация 100-400 байт в настройках клиента |
| Низкая скорость | `python ssh_exec.py exec "sysctl net.ipv4.tcp_congestion_control"` | Должен быть BBR. Если нет: `python ssh_exec.py deploy optimize-server.sh` |
| VPS IP заблокирован | Не подключается ни через один порт | Переключиться на Layer 1 (Yandex Cloud relay) |
| Мобильная сеть с белыми списками | Layer 0 не работает на LTE, работает на Wi-Fi | Layer 1: `deploy-relay-sweden.sh` + `deploy-relay-yc.sh` |
| Ничего не работает | Ни один layer не помогает | Layer 2: WebRTC через Телемост (`deploy-olcrtc-server.sh`) |
| 3X-UI панель недоступна | `python ssh_exec.py exec "systemctl status x-ui"` | `python ssh_exec.py exec "systemctl restart x-ui"` |

## Известные проблемы

| Проблема | Решение |
|----------|---------|
| `flow xtls-rprx-vision` — sing-box core не передаёт flow | Отключён на сервере, без flow работает стабильно |
| Мобильные операторы (МТС, Мегафон) блокируют агрессивнее Wi-Fi | TLS-фрагментация 100-400 байт в клиенте |
| SSH порт 22 блокируется ТСПУ к зарубежным IP | quick-rebuild.sh автоматически меняет на 49152 |
| Hiddify "Системный прокси" — QUIC/UDP утечка, Google/Claude видят РФ | **Использовать v2rayN с TUN-режимом** (см. docs/05-security.md) |
| v2rayN + Xray core — QUIC ломается через SOCKS5 handoff | **Использовать sing-box core** в v2rayN (Settings → Core Type) |
| Hiddify режим "VPN" — ошибка "failed to start background core" | Использовать v2rayN вместо Hiddify |
| NekoBox/Nekoray — проект архивирован (март 2025) | Мигрировать на v2rayN |
| v2rayN нет кнопки "Отключить VPN" | Toggle "Enable Tun" внизу окна |
| Cloudflare CDN заблокирован ТСПУ с 2025 | Использовать Layer 1 (Yandex Cloud) вместо Layer 3 |
| OlcRTC (Layer 2) пока только десктоп | Мобильное приложение ещё не создано. Для мобильных использовать Layer 1 |
