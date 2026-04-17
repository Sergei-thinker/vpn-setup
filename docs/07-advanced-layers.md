# 7. Продвинутые уровни защиты

> **UPDATE 2026-04-17 по фидбеку к статье [Habr 1021160](https://habr.com/ru/articles/1021160/):**
>
> **Миф «IP Yandex Cloud в белых списках ТСПУ» опровергается** (критика `@paxlo`, `@aax`, `@Varpun` в комментах). AS `Yandex.Cloud LLC` (пользовательские VM, подсети `51.250.x.x`, `212.233.x.x`) и AS `YANDEX LLC` (сервисы Яндекса) — разные автономные системы, ТСПУ фильтрует их раздельно. На части регионов YC-relay уже блокируется при активных белых списках. `@s5384` также отметил: IP-диапазоны YC во многих спам-базах, токсичные для legit-трафика. **Мораль:** YC relay использовать только как один из нескольких вариантов, не как гарантированный обход белых списков.

## Layer 0.5: nginx SNI-split со своим доменом (опционально)

### Зачем

Критика к VLESS Reality на порту 443 с чужим SNI `www.microsoft.com`: `@ice938`, `@Barnaby`, `@SPNkd` в комментариях указали, что ClientHello с `SNI=www.microsoft.com`, приходящий на IP хостера (не Microsoft), — очевидная аномалия для DPI. Легитимнее — свой домен.

### Архитектура

```
Клиент (SNI=ваш-домен.top)  → nginx:443 → nginx статика (заглушка Portfolio)
Клиент (SNI=www.ms.com)     → nginx:443 → xray:10443 (Reality)
Клиент (SNI=dl.google.com)  → nginx:443 → xray:10444 (Reality)
```

nginx работает как **stream SNI-router** (`ssl_preread on`): читает SNI из ClientHello без расшифровки, мапит по имени на backend. Xray больше не открыт на 443 напрямую — слушает только 127.0.0.1:{10443,10444,10453}. Внешнему наблюдателю IP VPS выглядит как «хостинг сайта your-domain.top» с basic_auth-закрытой заглушкой — паттерн обычный, не детектируется как прокси.

### Деплой

```bash
# Предварительно: A-запись your-domain.top на IP VPS (без Cloudflare Proxy)
# STUB_DOMAIN=your-domain.top bash deploy-sni-split.sh
STUB_DOMAIN=xk127r.top bash deploy-sni-split.sh
```

Скрипт идемпотентен: nginx + certbot + Let's Encrypt → static-заглушка на `/var/www/$DOMAIN` → nginx stream config с `ssl_preread` → меняет Reality inbound listen с `0.0.0.0:443` на `127.0.0.1:10443/10444/10453`.

### Когда включать

Не по умолчанию — только если обычный Reality начали детектировать (падения на конкретных операторах), либо на мобильных с агрессивным DPI. Плата за легитимность: ТСПУ может по IP VPS забанить всё, что на нём, включая заглушку — тогда Layer 0.5 перестаёт помогать.

Источник рецепта: `@ice938` в комментах к статье 1021160 (nginx.conf с полной конфигурацией).

---

## Relay-цепочка через российский VPS (Layer 1)

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

## Устаревшее: Yandex Cloud как relay

> **UPDATE 2026-04-17:** Ранее этот раздел описывал провизию preemptible VM в Yandex Cloud с расчётом, что IP YC-VM находятся в белых списках ТСПУ. **По критике в комментах к [Habr 1021160](https://habr.com/ru/articles/1021160/) (@paxlo, @aax, @Varpun) тезис опровергнут:** AS `Yandex.Cloud LLC` (пользовательские VM, подсети `51.250.x.x`, `212.233.x.x`) и AS `YANDEX LLC` (сервисы Яндекса) — разные автономные системы, ТСПУ фильтрует их раздельно. На ряде регионов YC-VM блокируется при активных белых списках. **Мораль:** YC как «гарантированный обход белых списков» не работает. Скрипты `deploy-relay-yc.sh`, `rotate-relay-yc.sh`, `yc-cloud-init.yaml.tpl` удалены 2026-04-17. Используйте generic RU VPS (см. раздел выше).

---

## Аварийные методы (Layer 2) — WebRTC через Яндекс.Телемост

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

**Когда использовать:** полный white-list режим, когда ВСЕ остальные методы заблокированы (Layer 0, 1 недоступны).

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

---

## CDN-фронтинг через Cloudflare (Layer 3)

> **Обновление (апрель 2026):** С середины 2025 Cloudflare **активно блокируется** ТСПУ. При белых списках на мобильной сети Layer 3 **не работает**. Используйте Layer 1 (relay на российском VPS — Timeweb/VDSina/Selectel). Layer 3 остаётся полезным только на домашнем Wi-Fi.

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
       -> Cloudflare CDN (IP ранее в белых списках ТСПУ, сейчас блокируется)
       -> Worker проксирует WebSocket на path /ws-vless-YOUR_SECRET_PATH
       -> VPS:2082 (VLESS WS inbound на сервере)
       -> Интернет
```

ТСПУ видит подключение к IP Cloudflare с SNI `your-domain.com` — выглядит как обычный сайт.
Обычные HTTP-запросы к домену показывают страницу "Coming Soon" (маскировка).

### Настройка клиента (Layer 3)

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

## Дополнительные методы

### ECH (Encrypted Client Hello)

Шифрует поле SNI в TLS ClientHello — DPI не видит к какому домену подключение.
- Автоматически работает через Cloudflare (Layer 3)
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
