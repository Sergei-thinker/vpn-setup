# VPN Infrastructure -- Инструкции для Claude Code

## Описание проекта

Многоуровневая VPN-инфраструктура на базе **VLESS Reality** для обхода ТСПУ/DPI блокировок в России.

- **Протокол:** VLESS + XTLS Reality (трафик неотличим от HTTPS к microsoft.com/google.com/apple.com)
- **Панель управления:** 3X-UI + Xray-core
- **Клиенты:** Hiddify (Windows/macOS), Shadowrocket (iOS), v2rayNG (Android)
- **Подробное руководство для ручной настройки:** [GUIDE.md](GUIDE.md)

## Архитектура: 4 уровня защиты

Каждый следующий уровень активируется когда предыдущий заблокирован.

**Приоритет: Layer 0 → Layer 2 → Layer 3 → Layer 1**

| Layer | Метод | Роль | Статус |
|-------|-------|------|--------|
| 0 | VLESS Reality (прямое, порты 443/8443/2053) | **Основной** | Работает |
| 2 | Relay через Yandex Cloud (xHTTP, SNI: yandex.ru) | **Главный fallback** -- обход белых списков на мобильных | Работает |
| 3 | WebRTC через Яндекс.Телемост (OlcRTC) | Аварийный (только Windows/Linux) | Скрипты готовы |
| 1 | Cloudflare CDN (WebSocket через домен пользователя) | Legacy backup (только домашний Wi-Fi) | Заблокирован ТСПУ с 2025 |

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
│   └── relay-config.md          # Настройка клиента для relay (Layer 2)
│
├── cloudflare-worker/           # Cloudflare Worker -- CDN-фронтинг (Layer 1)
│   ├── README.md                # Инструкция по деплою Worker
│   ├── worker.js                # WebSocket-прокси (маскировка под "Coming Soon")
│   └── wrangler.toml            # Конфигурация Wrangler
│
├── quick-rebuild.sh             # Полная установка VPN с нуля на чистый VPS
├── deploy-multilayer.sh         # Деплой multi-layer inbound-ов на существующий VPS
├── deploy-relay-sweden.sh       # Создание xHTTP inbound на зарубежном VPS (Layer 2)
├── deploy-relay.sh              # Полный деплой relay на российском VPS -- generic (Layer 2)
├── deploy-relay-yc.sh           # Провизия relay VM в Yandex Cloud (Layer 2, рекомендуемый)
├── deploy-olcrtc-server.sh      # Установка OlcRTC-сервера на VPS (Layer 3)
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

**После деплоя -- настроить split routing:**
- Дать пользователю конфиг из `client-configs/` для его платформы
- См. `client-configs/README.md` для инструкций

### Layer 2: Relay через Yandex Cloud (рекомендуемый backup)

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

### Layer 3: WebRTC через Телемост (аварийный, только десктоп)

**Когда нужен:** полная блокировка, ничего не работает.
**Ограничение:** только Windows (через WSL) и Linux. iOS/Android НЕ поддерживаются.
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

### Layer 1: Cloudflare CDN (legacy backup, только домашний Wi-Fi)

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

### Relay VPS (Layer 2)
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
| VPS IP заблокирован | Не подключается ни через один порт | Переключиться на Layer 2 (Yandex Cloud relay) |
| Мобильная сеть с белыми списками | Layer 0 не работает на LTE, работает на Wi-Fi | Layer 2: `deploy-relay-sweden.sh` + `deploy-relay-yc.sh` |
| Ничего не работает | Ни один layer не помогает | Layer 3: WebRTC через Телемост (`deploy-olcrtc-server.sh`) |
| 3X-UI панель недоступна | `python ssh_exec.py exec "systemctl status x-ui"` | `python ssh_exec.py exec "systemctl restart x-ui"` |

## Известные проблемы

| Проблема | Решение |
|----------|---------|
| `flow xtls-rprx-vision` вызывает panic XtlsPadding в Xray | Не использовать flow -- в конфигах уже отключён |
| Мобильные операторы (МТС, Мегафон) блокируют агрессивнее Wi-Fi | TLS-фрагментация 100-400 байт в клиенте |
| SSH порт 22 блокируется ТСПУ к зарубежным IP | quick-rebuild.sh автоматически меняет на 49152 |
| Hiddify режим "VPN" -- ошибка "failed to start background core" | Использовать режим "Системный прокси" |
| Cloudflare CDN заблокирован ТСПУ с 2025 | Использовать Layer 2 (Yandex Cloud) вместо Layer 1 |
| OlcRTC (Layer 3) работает только на десктопе | Для мобильных использовать Layer 2 |

## Документация

| Документ | Содержание |
|----------|-----------|
| [GUIDE.md](GUIDE.md) | Полное руководство для ручной настройки |
| [docs/README.md](docs/README.md) | Индекс документации |
| [docs/02-architecture.md](docs/02-architecture.md) | Архитектура, матрица inbound-ов |
| [docs/03-server-setup.md](docs/03-server-setup.md) | Настройка VPS, 3X-UI, VLESS Reality |
| [docs/04-client-setup.md](docs/04-client-setup.md) | Клиенты: Hiddify, Shadowrocket, v2rayNG |
| [docs/05-security.md](docs/05-security.md) | Hardening, оптимизация для мобильных |
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
