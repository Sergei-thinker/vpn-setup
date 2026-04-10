# 7. Продвинутые уровни защиты

## CDN-фронтинг через Cloudflare (Layer 1)

### Почему это ключевое улучшение

> **Обновление (апрель 2026):** С середины 2025 Cloudflare **активно блокируется** ТСПУ. При белых списках на мобильной сети Layer 1 **не работает**. Используйте Layer 2 (Yandex Cloud relay) для обхода белых списков. Layer 1 остаётся полезным на домашнем Wi-Fi.

IP-адреса Cloudflare (104.16.0.0/12, 172.64.0.0/13) ранее находились в белых списках ТСПУ, потому что тысячи российских сайтов используют Cloudflare.

```
Клиент -> Cloudflare CDN (белый список) -> Ваш VPS -> Интернет
          SNI: ваш домен через CF         WebSocket relay
```

### Текущая конфигурация (реализовано)

| Параметр | Значение |
|----------|----------|
| Домен | `your-domain.com` (Namecheap, ~$6/год, первый год ~$3) |
| Cloudflare | Бесплатный план, Proxy ON |
| DNS | A `your-domain.com` -> VPS IP (Proxied) |
| DNS | A `www.your-domain.com` -> VPS IP (Proxied) |
| SSL/TLS | Full |
| Worker | `vpn-ws-proxy` |
| Worker route | `your-domain.com/*` |
| Backend | VPS_IP:2082 (VLESS WebSocket) |
| WS Path | `/ws-vless-YOUR_SECRET_PATH` |

### Как это работает

```
Клиент -> your-domain.com:443 (HTTPS/WSS)
       -> Cloudflare CDN (IP в белых списках ТСПУ!)
       -> Worker проксирует WebSocket на path /ws-vless-YOUR_SECRET_PATH
       -> VPS:2082 (VLESS WS inbound на сервере)
       -> Интернет
```

ТСПУ видит подключение к IP Cloudflare с SNI `your-domain.com` — выглядит как обычный сайт.
Обычные HTTP-запросы к домену показывают страницу "Coming Soon" (маскировка).

### Настройка клиента (Layer 1)

| Поле | Значение |
|------|----------|
| Protocol | VLESS |
| Address | `your-domain.com` (НЕ IP!) |
| Port | 443 |
| UUID | (из панели 3X-UI) |
| Transport | **WebSocket** |
| Path | `/ws-vless-YOUR_SECRET_PATH` |
| TLS | **ON** |
| SNI | `your-domain.com` |
| Flow | пусто |

### Альтернативный путь через workers.dev

Если домен `your-domain.com` заблокируют (маловероятно), можно подключаться напрямую к Worker:
- Адрес: `vpn-ws-proxy.your-worker.workers.dev`
- Порт: 443
- Остальное — то же самое

SNI будет показывать `workers.dev` (домен Cloudflare) — ещё сложнее заблокировать.

### Управление Worker

```bash
# Обновить Worker
cd cloudflare-worker
CLOUDFLARE_API_TOKEN=... npx wrangler deploy

# Логи в реальном времени
CLOUDFLARE_API_TOKEN=... npx wrangler tail
```

Подробная инструкция: [cloudflare-worker/README.md](../cloudflare-worker/README.md)

---

## Relay-цепочка через российский VPS (Layer 2)

### Когда нужна
Если IP шведского VPS заблокирован целиком и Cloudflare CDN тоже недоступен.

### Схема
```
Устройство -> VPS в РФ (Timeweb, ~80 RUB/мес) -> VPS Швеция -> Интернет
              VLESS Reality                       xhttp relay
              SNI: gosuslugi.ru                   
```

### Автоматизация деплоя

Для развёртывания relay подготовлены скрипты:

| Скрипт | Назначение |
|--------|-----------|
| `deploy-relay-sweden.sh` | Создаёт xHTTP inbound (relay-xhttp, порт 10443) на шведском VPS |
| `deploy-relay.sh` | Полный деплой relay на российском VPS (Xray-core + конфиг + мониторинг) |
| `monitor-relay.sh` | Health check обоих VPS (шведский + российский) |

**Порядок деплоя:**
1. Запустить `deploy-relay-sweden.sh` на шведском VPS — создаст принимающий inbound
2. Арендовать VPS в РФ: Timeweb Cloud (~80 RUB/мес), VDSina (~100 RUB/мес)
3. Запустить `deploy-relay.sh` на российском VPS — настроит полную relay-цепочку
4. Настроить клиент по инструкции в `client-configs/relay-config.md`

**Управление relay:**
```bash
python ssh_exec.py -t relay status    # Статус relay VPS
python ssh_exec.py -t relay logs      # Логи relay VPS
python ssh_exec.py -t relay restart   # Перезапуск relay
python ssh_exec.py relay-status       # Статус обоих VPS одновременно
bash monitor-relay.sh                 # Health check обоих VPS
```

### Настройка российского VPS (relay) — ручная

Если нужна ручная настройка без скриптов:

1. Арендовать VPS: Timeweb Cloud (~80 RUB/мес), VDSina (~100 RUB/мес)
2. Установить Xray-core:
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

3. Конфиг relay (`/usr/local/etc/xray/config.json`):
```json
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "<UUID>", "flow": ""}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "www.gosuslugi.ru:443",
        "serverNames": ["www.gosuslugi.ru"],
        "privateKey": "<PRIVATE_KEY>",
        "shortIds": ["<SHORT_ID>"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "<SWEDEN_VPS_IP>",
        "port": 10443,
        "users": [{"id": "<UUID>", "flow": "", "encryption": "none"}]
      }]
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "serverName": "www.microsoft.com",
        "fingerprint": "chrome",
        "publicKey": "<PUBLIC_KEY>",
        "shortId": "<SHORT_ID>"
      },
      "xhttpSettings": {"mode": "packet-up"}
    }
  }]
}
```

### Риски (generic VPS)
- Российские VPS-провайдеры детектируют прокси-трафик (статья Habr 1020114)
- IP generic-хостингов (Timeweb, VDSina) **не гарантированно в белых списках** мобильных операторов
- **Митигация:** xhttp packet-up mode, минимизировать трафик, иметь запасного провайдера

---

## Relay через Yandex Cloud (Layer 2, рекомендуемый)

### Почему Yandex Cloud

С середины 2025 Cloudflare активно блокируется ТСПУ. При белых списках на мобильной сети (МТС, Мегафон) пропускаются только российские IP. **IP Yandex Cloud подтверждённо в белых списках** (добавлен 19.09.2025).

### Архитектура

```
Клиент → Yandex Cloud VM:15443 (VLESS Reality, SNI: yandex.ru)
         [IP в белом списке ТСПУ]
         │
         └─→ Swedish VPS:10443 (VLESS xHTTP Reality, SNI: microsoft.com)
             │
             └─→ Интернет
```

### Отличия от generic relay

| Параметр | Generic VPS | Yandex Cloud |
|----------|-------------|--------------|
| IP в белых списках | Не гарантировано | Да |
| SNI | gosuslugi.ru | yandex.ru (нативный) |
| Порт relay | 443 | 15443 (декой nginx на 443) |
| Декой | Нет | Nginx с фейковым сайтом |
| Провизия | SSH-скрипт | yc CLI + cloud-init |
| Детекция | Базовая | ML (SmartWebSecurity) |
| Стоимость | ~80 RUB/мес | ~400 RUB/мес (preemptible) |

### Anti-detection

| Мера | Зачем |
|------|-------|
| Nginx декой на 80/443 | VM выглядит как обычный веб-сервер |
| Xray на порту 15443 | Не конфликтует с декоем |
| SNI: yandex.ru | Нативный для Yandex Cloud IP |
| Cloud-init | VM "рождается настроенной", без SSH-скриптов |
| Низкий трафик | < 50 GB/мес (лимит free tier: 100 GB) |

### Скрипты

| Скрипт | Назначение |
|--------|-----------|
| `deploy-relay-sweden.sh` | Создаёт xHTTP inbound на шведском VPS (порт 10443) |
| `deploy-relay-yc.sh` | Провизия VM в Yandex Cloud через `yc` CLI |
| `rotate-relay-yc.sh` | Авто-рестарт preemptible VM, обновление IP |
| `monitor-relay.sh` | Health check (включая проверку YC VM) |

### Деплой

```bash
# 1. Подготовка шведского VPS (один раз)
python ssh_exec.py deploy deploy-relay-sweden.sh

# 2. Заполнить .env: YC_FOLDER_ID, SWEDEN_RELAY_UUID, SWEDEN_RELAY_PUBKEY, SWEDEN_RELAY_SID

# 3. Провизия VM в Yandex Cloud
bash deploy-relay-yc.sh

# 4. (Для preemptible) Добавить в cron:
# */5 * * * * /path/to/rotate-relay-yc.sh --cron >> /var/log/yc-relay-rotate.log 2>&1
```

### Управление

```bash
python ssh_exec.py yc-status                 # Статус YC VM (без SSH)
python ssh_exec.py -t relay status           # Статус через SSH
python ssh_exec.py -t relay logs             # Логи Xray
bash rotate-relay-yc.sh                      # Рестарт если STOPPED
bash monitor-relay.sh                        # Полный health check
```

### Preemptible VM

Preemptible VM стоит ~4x дешевле, но останавливается через 24ч. `rotate-relay-yc.sh` автоматически перезапускает и обновляет `.env` при смене IP.

**Если IP меняется часто** — рассмотрите статический IP (+100 RUB/мес) или non-preemptible VM (~1800 RUB/мес).

### Fallback

```
Yandex Cloud заблокировали → RELAY_PROVIDER=vk, deploy-relay.sh на VK Cloud
VK Cloud не работает       → RELAY_PROVIDER=generic, deploy-relay.sh на Timeweb
Всё заблокировано          → Layer 3 (WebRTC/DNS-туннель)
```

---

## Аварийные методы (Layer 3)

### WebRTC через Яндекс.Телемост (OlcRTC)

Из статьи [Habr 1020114](https://habr.com/ru/articles/1020114/) (опубликована 7 апреля 2026) — туннелирование данных через WebRTC DataChannel сервиса Яндекс.Телемост.

**Принцип работы:** OlcRTC создаёт WebRTC-соединение через SFU-сервер Яндекс.Телемоста, используя DataChannel (SCTP over DTLS) для передачи произвольных данных. ТСПУ не может заблокировать трафик к Яндексу, так как он в белом списке.

| Параметр | Значение |
|----------|----------|
| Пропускная способность | До 44 Mbps (реальные тесты) |
| Латентность | ~57ms (100 байт), ~130ms (8KB) |
| Протокол | DataChannel (SCTP over DTLS over ICE) |
| Ограничение сообщения | 8KB максимум (ограничение SCTP) |
| Платформы | **Linux only** (Go + Python); Windows через WSL2 |
| Репозиторий | [`zarazaex69/olcRTC`](https://github.com/zarazaex69/olcRTC) на GitHub |
| Статус | Исследование завершено, скрипты в разработке |

**Когда использовать:** полный white-list режим, когда ВСЕ остальные методы заблокированы (Layer 0, 1, 2 недоступны).

**Как развернуть:**
```bash
# На VPS (второй участник конференции)
bash <(curl -sL zarazaex.xyz/srv.sh)

# На клиенте (Linux или WSL2 на Windows)
bash <(curl -sL zarazaex.xyz/cnc.sh)
# Ввести conference ID и ключ шифрования
# Локальный SOCKS5 прокси на порту 8809
```

**Технические детали DataChannel:**
- Максимальный размер сообщения: 8KB (ограничение SCTP буфера)
- Для больших пакетов данные фрагментируются на стороне клиента
- Шифрование: DTLS 1.2+ (обеспечивается WebRTC стеком)
- Сигналинг: через API Яндекс.Телемоста (создание/вход в конференцию)

**Ограничения:**
- **Linux only** — нативный клиент работает только на Linux; на Windows требуется WSL2
- Не маскирует трафик под реальные видеозвонки (нет аудио/видео потоков)
- Ручное создание конференций (нет автоматического reconnect)
- Яндекс может ограничить DataChannel в будущем
- 8KB лимит на сообщение снижает эффективность для больших потоков данных

### ECH (Encrypted Client Hello)

Шифрует поле SNI в TLS ClientHello — DPI не видит к какому домену подключение.
- Автоматически работает через Cloudflare (Layer 1)
- Xray-core пока не поддерживает нативно
- Chrome 117+ и Firefox 118+ поддерживают на стороне клиента

### QUIC transport

UDP-based, может обойти TCP-фокусированный DPI. Но:
- Многие российские операторы блокируют/замедляют неизвестный UDP
- Тестировать осторожно
- Не рекомендуется как основной вариант

### Локальный обход DPI (без сервера)

| Инструмент | Платформа | Метод |
|------------|-----------|-------|
| [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) | Windows | Фрагментация TCP/TLS |
| [zapret](https://github.com/bol-van/zapret) | Linux | Фрагментация TCP/TLS |
| ByeDPI | Android | Фрагментация TCP/TLS |

Работает только на домашнем Wi-Fi, на мобильном LTE обычно нет.
