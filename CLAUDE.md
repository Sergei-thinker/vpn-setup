# VPN Infrastructure -- Инструкции для Claude Code

## Как работать с пользователем

Пользователь может прийти по-разному:
1. **Клонировал репозиторий** и просит "разверни VPN" -- перейти к деплою (проверить .env)
2. **Скинул ссылку на этот репо** и просит развернуть VPN -- объяснить что нужно:
   - Арендовать VPS (~$2-5/мес): любой EU-провайдер вне РФ (Нидерланды/Швеция/Финляндия/Германия, Debian 12). НЕ российские хостинги (Aeza, VDSina, REG.RU — подчиняются РКН). НЕ крупные облака (Hetzner/OVH/DigitalOcean — IP-диапазоны блокируются ТСПУ)
   - Установить VPN-клиент: v2rayN (Windows, бесплатно), Shadowrocket (iOS, $2.99), v2rayNG (Android, бесплатно)
   - Дать IP-адрес VPS и SSH-доступ
   - Затем: клонировать репо, заполнить .env, запустить деплой
3. **Спрашивает что это** -- объяснить кратко и предложить помочь с установкой

Общайся с пользователем на **русском языке**.

## Описание проекта

Многоуровневая VPN-инфраструктура на базе **VLESS Reality** для обхода ТСПУ/DPI блокировок в России.

- **Протокол:** VLESS + XTLS Reality (трафик неотличим от HTTPS к microsoft.com/google.com/apple.com)
- **Панель управления:** 3X-UI + Xray-core
- **Клиенты:** v2rayN (Windows, рекомендуемый), Hiddify (альтернатива), Shadowrocket (iOS), v2rayNG (Android)
- **Подробное руководство для ручной настройки:** [GUIDE.md](GUIDE.md)

## Архитектура

Каждый следующий уровень активируется когда предыдущий заблокирован.

| Layer | Метод | Роль | Статус |
|-------|-------|------|--------|
| 0 | VLESS Reality (прямое, порты 443/8443/2053) | **Основной** | Работает |
| 1 | Relay через Yandex Cloud (xHTTP, SNI: yandex.ru) | **Главный fallback** -- обход белых списков на мобильных | Работает |
| 2 | WebRTC через Яндекс.Телемост (OlcRTC) | Аварийный (пока только десктоп -- мобильное приложение OlcRTC ещё не создано) | Скрипты готовы |
| 3 | Cloudflare CDN (WebSocket через домен пользователя) | Backup для Wi-Fi (Cloudflare блокируется ТСПУ с 2025) | Работает только на Wi-Fi |

**Split routing:** Российские сайты (Yandex, VK, Госуслуги, банки) идут напрямую, минуя VPN.

## Предварительные требования

Перед деплоем убедись что:

1. **`.env` файл заполнен** -- пользователь скопировал `.env.example` → `.env` и вписал:
   - `VPN_HOST` -- IP-адрес VPS
   - `VPN_SSH_PORT` -- SSH порт (по умолчанию 22, но ТСПУ часто блокирует 22 для зарубежных IP -- рекомендуется 49152)
   - `VPN_SSH_USER` -- обычно `root`
   - `VPN_SSH_KEY` или `VPN_SSH_PASS` -- SSH-ключ или пароль
2. **VPS с Debian 12** -- чистая установка, root-доступ
3. **Python 3** с `paramiko` -- для ssh_exec.py (`pip install paramiko`)

## Пошаговый деплой

### Layer 0: VLESS Reality (основной -- деплоить ВСЕГДА)

```bash
# 1. Проверить подключение к VPS
python ssh_exec.py status

# 2. Задеплоить VPN (полная установка с нуля)
python ssh_exec.py deploy quick-rebuild.sh

# 3. Скрипт выведет VLESS URI -- дать пользователю для импорта в клиент
# Формат: vless://UUID@IP:PORT?...#имя-подключения

# 4. Проверить что всё работает
python ssh_exec.py status
```

**Что делает quick-rebuild.sh:**
- Устанавливает 3X-UI панель управления
- Создаёт 3 VLESS Reality inbound-а (порты 443, 8443, 2053) с разными SNI
- Настраивает BBR и sysctl для оптимальной производительности
- Настраивает firewall (ufw)
- Меняет SSH-порт на 49152 (обход блокировки ТСПУ)
- Выводит VLESS URI для каждого inbound-а

**После деплоя -- настроить клиент:**
- **Windows:** дать пользователю инструкцию `client-configs/v2rayn-setup.md` (v2rayN + TUN-режим обязателен)
- **iOS:** Shadowrocket (рекомендуется) или v2RayTun — см. `docs/04-client-setup.md`
- **Android:** v2rayNG — см. `docs/04-client-setup.md`
- **Split routing:** дать конфиг из `client-configs/` для его платформы (см. `client-configs/README.md`)

### Layer 1: Relay через Yandex Cloud (рекомендуемый backup)

**Когда нужен:** мобильная сеть с белыми списками, IP VPS заблокирован.
**Почему работает:** IP-адреса Yandex Cloud в белых списках ТСПУ.

```bash
# 1. Настроить xHTTP inbound на зарубежном VPS (принимающая сторона)
python ssh_exec.py deploy deploy-relay-sweden.sh

# 2. Заполнить .env: SWEDEN_RELAY_UUID, SWEDEN_RELAY_PUBKEY, SWEDEN_RELAY_SID
#    (скрипт deploy-relay-sweden.sh выведет эти значения)

# 3. Создать relay VM в Yandex Cloud
#    Нужен: yc CLI (https://cloud.yandex.ru/docs/cli/quickstart)
#    Нужен: YC_FOLDER_ID в .env
bash deploy-relay-yc.sh

# 4. Дать пользователю relay VLESS URI
```

**Альтернатива Yandex Cloud:** `deploy-relay.sh` -- деплой relay на любой российский VPS (Timeweb, VDSina и др.)

### Layer 2: WebRTC через Телемост (аварийный, пока только десктоп)

**Когда нужен:** полная блокировка, ничего не работает.
**Ограничение:** пока только Windows (через WSL) и Linux. Мобильное приложение OlcRTC ещё не создано.
**Скорость:** до 44 Mbps.

```bash
# 1. Установить OlcRTC-сервер на VPS
python ssh_exec.py deploy deploy-olcrtc-server.sh

# 2. Пользователь создаёт конференцию: https://telemost.yandex.ru
# 3. Запускает клиент:
#    Windows: olcrtc-client.bat
#    Linux/WSL: bash olcrtc-wsl-client.sh
# 4. SOCKS5 прокси на localhost:8809 → подключить в Hiddify
```

### Layer 3: Cloudflare CDN (backup, только домашний Wi-Fi)

**ВНИМАНИЕ:** Cloudflare активно блокируется ТСПУ с 2025. Работает только на домашнем Wi-Fi.

Требуется: домен пользователя + Cloudflare аккаунт.

```bash
# 1. Пользователь привязывает домен к Cloudflare (NS-серверы)
# 2. Пользователь добавляет A-запись: домен → IP VPS (Proxied/оранжевое облако)
# 3. Деплой Worker:
cd cloudflare-worker
# Отредактировать wrangler.toml: BACKEND_HOST = IP VPS
CLOUDFLARE_API_TOKEN=... npx wrangler deploy

# 4. Настроить клиент: WSS подключение через домен пользователя
```

Подробная инструкция: `cloudflare-worker/README.md`

## Команды управления (ssh_exec.py)

### Основной VPS
```bash
python ssh_exec.py status              # Статус xray, uptime, соединения
python ssh_exec.py restart             # Перезапуск x-ui/xray
python ssh_exec.py logs                # Последние логи Xray
python ssh_exec.py logs -n 100         # Последние 100 строк логов
python ssh_exec.py exec "command"      # Произвольная SSH-команда
python ssh_exec.py deploy script.sh    # Загрузить и выполнить скрипт на VPS
python ssh_exec.py backup              # Скачать бэкап x-ui.db
python ssh_exec.py update-xray         # Обновить Xray-core до последней версии
```

### Relay VPS (Layer 1)
```bash
python ssh_exec.py -t relay status     # Статус relay VPS
python ssh_exec.py -t relay restart    # Перезапуск relay
python ssh_exec.py -t relay logs       # Логи relay
python ssh_exec.py relay-status        # Статус обоих VPS одновременно
bash monitor-relay.sh                  # Health check обоих VPS
```

### Деплой скриптов
```bash
# Полная пересборка VPN с нуля (disaster recovery)
python ssh_exec.py deploy quick-rebuild.sh

# Добавить multi-layer к существующему серверу
python ssh_exec.py deploy deploy-multilayer.sh

# Деплой relay на российский VPS
python ssh_exec.py deploy deploy-relay.sh
```

## Справочная документация

- Индекс документации: `docs/README.md`
- Troubleshooting и известные проблемы: `docs/08-operations.md`
- Split routing: `client-configs/README.md`

## Правила

- **Язык общения с пользователем:** русский
- **Credentials** хранить ТОЛЬКО в `.env`, НИКОГДА не коммитить в git и не показывать в output
- **Скрипты идемпотентны** -- безопасно запускать повторно
- **Тестирование VPN:** 2ip.ru (должен показать российский IP для российских сайтов, зарубежный IP для остальных)
- При деплое всегда сначала проверять `python ssh_exec.py status` -- убедиться что VPS доступен
