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
5. Если IP заблокирован целиком -> переключиться на Cloudflare CDN path
6. Если всё заблокировано -> использовать relay через российский VPS
7. **Крайний случай:** пересоздать сервер (`quick-rebuild.sh`)

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

## Relay VPS (Layer 2) — Управление

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

1. **Удалить старый сервер** в Aeza (или другом провайдере)
2. **Создать новый** (тот же тариф SWE-PROMO, 1.99 EUR)
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
