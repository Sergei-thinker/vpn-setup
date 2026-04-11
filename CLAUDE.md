# VPN Infrastructure -- Инструкции для Claude Code

## Как работать с пользователем

Пользователь может прийти по-разному:
1. **Клонировал репозиторий** и просит "разверни VPN" -- перейти к деплою (проверить .env)
2. **Скинул ссылку на этот репо** и просит развернуть VPN -- объяснить что нужно:
   - Арендовать VPS (~$2/мес): Aeza.net, 4VPS, Fornex (Швеция/Финляндия/Германия, Debian 12). НЕ Hetzner/OVH/DigitalOcean (заблокированы)
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

## Структура проекта

```
vpn-setup/
├── CLAUDE.md                    # Этот файл -- инструкции для Claude Code
├── README.md                    # Описание проекта для пользователей
├── GUIDE.md                     # Полное руководство для ручной настройки
│
├── docs/                        # Документация (разбита по темам)
│   ├── README.md                # Индекс документации
│   ├── 01-overview.md           # Зачем VPN, как работают блокировки, выбор технологии
│   ├── 02-architecture.md       # Многоуровневая архитектура, матрица inbound-ов
│   ├── 03-server-setup.md       # Пошаговая настройка VPS + 3X-UI + VLESS Reality
│   ├── 04-client-setup.md       # Настройка клиентов (Windows, iOS, Android, macOS)
│   ├── 05-security.md           # Безопасность, hardening, оптимизация для мобильных
│   ├── 06-split-routing.md      # Split routing -- российские сайты напрямую
│   ├── 07-advanced-layers.md    # CDN-фронтинг, Relay, аварийные методы
│   ├── 08-operations.md         # Мониторинг, обслуживание, troubleshooting
│   └── 09-status.md             # Текущий статус, бюджет, источники
│
├── client-configs/              # Конфиги split routing для клиентов
│   ├── README.md                # Инструкция по настройке routing
│   ├── shadowrocket-rules.conf  # iOS (Shadowrocket) -- 150+ RU доменов
│   ├── v2rayng-routing.json     # Android (v2rayNG)
│   ├── hiddify-routing.txt      # Windows (Hiddify)
│   ├── xray-server-routing.json # Серверный routing (3X-UI)
│   └── relay-config.md          # Настройка клиента для relay (Layer 1)
│
├── cloudflare-worker/           # Cloudflare Worker -- CDN-фронтинг (Layer 3)
│   ├── README.md                # Инструкция по деплою Worker
│   ├── worker.js                # WebSocket-прокси (маскировка под "Coming Soon")
│   └── wrangler.toml            # Конфигурация Wrangler
│
├── quick-rebuild.sh             # Полная установка VPN с нуля на чистый VPS
├── deploy-multilayer.sh         # Деплой multi-layer inbound-ов на существующий VPS
├── deploy-relay-sweden.sh       # Создание xHTTP inbound на зарубежном VPS (Layer 1)
├── deploy-relay.sh              # Полный деплой relay на российском VPS -- generic (Layer 1)
├── deploy-relay-yc.sh           # Провизия relay VM в Yandex Cloud (Layer 1, рекомендуемый)
├── deploy-olcrtc-server.sh      # Установка OlcRTC-сервера на VPS (Layer 2)
├── yc-cloud-init.yaml.tpl       # Шаблон cloud-init для YC VM
├── rotate-relay-yc.sh           # Авто-рестарт preemptible VM в Yandex Cloud
├── monitor-relay.sh             # Health check обоих VPS
├── optimize-server.sh           # Оптимизация BBR/TCP
├── ssh_exec.py                  # SSH-утилита управления сервером
├── olcrtc-client.bat            # OlcRTC клиент для Windows
├── olcrtc-wsl-client.sh         # OlcRTC клиент для WSL/Linux
│
├── .env                         # Credentials (НЕ коммитить!)
├── .env.example                 # Шаблон .env
└── .gitignore
```

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

## Split routing

Российские сайты должны идти напрямую (без VPN) -- это быстрее и не вызывает подозрений.

Готовые конфиги:
- **iOS (Shadowrocket):** `client-configs/shadowrocket-rules.conf`
- **Android (v2rayNG):** `client-configs/v2rayng-routing.json`
- **Windows (Hiddify):** `client-configs/hiddify-routing.txt`
- **Серверный routing:** `client-configs/xray-server-routing.json`

Инструкция по настройке: `client-configs/README.md`

## Troubleshooting

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

## Документация

| Документ | Содержание |
|----------|-----------|
| [GUIDE.md](GUIDE.md) | Полное руководство для ручной настройки |
| [docs/README.md](docs/README.md) | Индекс документации |
| [docs/02-architecture.md](docs/02-architecture.md) | Архитектура, матрица inbound-ов |
| [docs/03-server-setup.md](docs/03-server-setup.md) | Настройка VPS, 3X-UI, VLESS Reality |
| [docs/04-client-setup.md](docs/04-client-setup.md) | Клиенты: v2rayN (Windows), Shadowrocket (iOS), v2rayNG (Android) |
| [docs/05-security.md](docs/05-security.md) | Hardening, утечки QUIC/UDP, sing-box core, оптимизация |
| [client-configs/v2rayn-setup.md](client-configs/v2rayn-setup.md) | Пошаговая настройка v2rayN (Windows) |
| [docs/07-advanced-layers.md](docs/07-advanced-layers.md) | CDN Cloudflare, Relay, WebRTC |
| [docs/08-operations.md](docs/08-operations.md) | Мониторинг, troubleshooting |
| [client-configs/README.md](client-configs/README.md) | Настройка split routing |
| [cloudflare-worker/README.md](cloudflare-worker/README.md) | Деплой Cloudflare Worker |

## Правила

- **Язык общения с пользователем:** русский
- **Credentials** хранить ТОЛЬКО в `.env`, НИКОГДА не коммитить в git и не показывать в output
- **Скрипты идемпотентны** -- безопасно запускать повторно
- **Тестирование VPN:** 2ip.ru (должен показать российский IP для российских сайтов, зарубежный IP для остальных)
- При деплое всегда сначала проверять `python ssh_exec.py status` -- убедиться что VPS доступен
