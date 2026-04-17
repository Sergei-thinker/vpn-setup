# Инструкция по настройке VPN

> **English:** Multi-layer VPN system (VLESS Reality + Russian relay VPS + WebRTC) for bypassing Russian internet censorship (ТСПУ/DPI). Designed to be deployed automatically via [Claude Code](https://claude.ai/claude-code). See below for Russian documentation.

---

## Что это

VPN-инфраструктура на базе **VLESS Reality** -- протокола, который маскирует VPN-трафик под обычные HTTPS-запросы к Microsoft, Google и Apple. Для систем блокировки (ТСПУ/DPI) ваш трафик выглядит как обычный интернет-сёрфинг.

Если один метод подключения блокируют -- система автоматически переключается на следующий.

**Split routing:** российские сайты (банки, Госуслуги, VK, Yandex) идут напрямую, без VPN -- они работают быстрее и не вызывают подозрений.

## Как это работает

```
Приоритет подключения:

Layer 0: VLESS Reality        → VPS за рубежом → Интернет     ← основной
Layer 1: Russian Relay VPS    → VPS за рубежом → Интернет     ← если IP VPS заблокирован
Layer 2: WebRTC / Телемост    → VPS за рубежом → Интернет     ← аварийный
Layer 3: Cloudflare CDN       → VPS за рубежом → Интернет     ← backup для Wi-Fi
```

| Layer | Метод | Когда нужен | Платформы |
|-------|-------|-------------|-----------|
| **0** | **VLESS Reality** | Всегда, основной вариант | Все |
| **1** | **Russian Relay VPS** (Timeweb, VDSina, Selectel) | Мобильная сеть с белыми списками, IP основного VPS заблокирован | Все |
| **2** | **WebRTC / Телемост** | Полная блокировка, ничего не работает | Пока только десктоп (мобильное приложение OlcRTC ещё не создано) |
| **3** | **Cloudflare CDN** | Backup при блокировке IP VPS (только домашний Wi-Fi, т.к. Cloudflare блокируется ТСПУ с 2025) | Все |

> **Важно про Yandex Cloud:** ранее проект предлагал relay через Yandex Cloud preemptible VM как способ «попасть в белые списки ТСПУ». По фидбеку к [Habr 1021160](https://habr.com/ru/articles/1021160/) (комменты @paxlo, @aax, @Varpun) — это опровергается: AS `Yandex.Cloud LLC` и AS `YANDEX LLC` — разные автономные системы, ТСПУ фильтрует их раздельно. YC-VM уже блокируются при активных белых списках в ряде регионов. YC как гарантированный обход не работает, удалён из дефолтной архитектуры 2026-04-17. Используйте generic RU VPS (Timeweb/VDSina/Selectel) — шансы примерно те же, цена меньше.

## Что нужно сделать вам

### 1. Арендовать VPS (~$2/мес)

VPS -- это виртуальный сервер за рубежом, через который будет идти ваш трафик.

- **Рекомендуемые:** [AlphaVPS](https://alphavps.com/) (Болгария, от €3.50/мес), [Hetzner](https://www.hetzner.com/cloud/) (Германия, от €3.49/мес), [RackNerd](https://www.racknerd.com/) (от ~$1/мес) -- любой EU VPS с Debian 12
- **⛔ НЕ использовать российские хостинги:** Aeza, VDSina, REG.RU, Timeweb -- подчиняются Роскомнадзору и могут блокировать VPN по требованию
- **⚠️ Не рекомендуется:** Hetzner, OVH, DigitalOcean -- их подсети массово заблокированы ТСПУ (но если IP свежий -- может работать)
- **Что понадобится:** IP-адрес сервера и SSH-доступ (пароль или ключ)

### 2. Купить домен *(опционально)* (~$6/год, первый год ~$3)

Домен нужен для CDN-фронтинга через Cloudflare (backup). Без домена основной VPN и Yandex Cloud relay будут работать -- этого достаточно для большинства случаев.

- **Где:** [namecheap.com](https://www.namecheap.com/)
- **Какой:** любой дешёвый домен (`.top`, `.xyz`, `.site`)

### 3. Установить VPN-клиент на устройства

| Платформа | Приложение | Цена | Где скачать |
|-----------|-----------|------|-------------|
| **Windows** | **[v2rayN](https://v2rayn.2dust.link)** | Бесплатно | [GitHub](https://v2rayn.2dust.link/) |
| **macOS** | **[v2rayN](https://v2rayn.2dust.link)** | Бесплатно | [GitHub](https://v2rayn.2dust.link/) |
| **Android** | [v2rayNG](https://github.com/2dust/v2rayNG) | Бесплатно | Google Play / [GitHub](https://github.com/2dust/v2rayNG/releases) |
| **iOS** | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) | $2.99 | App Store |

> **⚠️ TUN-режим обязателен!** Без TUN (в режиме "Системный прокси") QUIC/UDP трафик идёт напрямую через провайдера — Google, Claude.ai и другие сервисы увидят ваш реальный IP. Подробнее: [docs/05-security.md](docs/05-security.md)

> **🛡️ Hardening 2026-04-17** (по фидбеку к статьям [Habr 1021160](https://habr.com/ru/articles/1021160/) и [1023224](https://habr.com/ru/articles/1023224/)): серверное блок-правило на 17 «узнай-свой-IP» эндпоинтов (`api.ipify.org`, `ifconfig.me`, `redirector.googlevideo.com` и т.д.) — защита от деанона VPS-IP через вкладки «стукачёвых» сайтов и российские desktop-приложения. Плюс ротация SNI в Reality (4 варианта на inbound) и опциональный Layer 0.5 (`deploy-sni-split.sh`) со своим доменом. Подробности: [docs/05-security.md](docs/05-security.md), [docs/habr-update-draft.md](docs/habr-update-draft.md).

> **Почему v2rayN?** Стабильный TUN-режим с sing-box core, встроенный пресет маршрутизации для России, корректная обработка QUIC/UDP. Работает на Windows, macOS и Linux.

> **Почему Shadowrocket на iOS?** Поддерживает VLESS Reality, WebSocket-транспорт, split routing и auto-select серверов. Лучший клиент для iOS.

## Установка VPN через Claude Code

[Claude Code](https://claude.ai/claude-code) -- AI-агент от Anthropic. Работает в терминале и как расширение для VS Code / JetBrains. Он прочитает инструкции из этого репозитория и автоматически настроит VPN на вашем сервере.

### Вариант 1: Клонировать репозиторий

```bash
# 1. Установите Claude Code (нужен Node.js 18+)
npm install -g @anthropic-ai/claude-code

# 2. Клонируйте репозиторий
git clone https://github.com/Sergei-thinker/vpn-setup.git
cd vpn-setup

# 3. Скопируйте шаблон конфигурации и заполните данные VPS
cp .env.example .env
# Отредактируйте .env — впишите IP вашего VPS и SSH-данные

# 4. Запустите Claude Code
claude
```

Скажите Claude: **"Разверни мне VPN"**

### Вариант 2: Просто скинуть ссылку

Если у вас уже установлен Claude Code -- просто откройте его и отправьте:

> Разверни мне VPN по инструкции из https://github.com/Sergei-thinker/vpn-setup

Claude сам клонирует репозиторий, объяснит что нужно сделать (арендовать VPS, заполнить `.env`), и проведёт вас через весь процесс шаг за шагом.

---

Claude автоматически:
- Установит панель 3X-UI и VLESS Reality на сервере
- Настроит несколько backup-подключений (разные порты и SNI)
- Сгенерирует ссылки для импорта в VPN-клиент
- Настроит split routing для российских сайтов
- Объяснит, как импортировать конфиг в ваше приложение

## Ручная установка (без Claude Code)

Если вы предпочитаете настроить всё самостоятельно -- подробная пошаговая инструкция: **[GUIDE.md](GUIDE.md)**

Для справки по конкретным темам: **[docs/](docs/)**

## Структура проекта

| Файл / Папка | Назначение |
|--------------|-----------|
| `CLAUDE.md` | Инструкции для Claude Code (AI-агент читает этот файл) |
| `GUIDE.md` | Полное руководство для ручной настройки |
| `docs/` | Документация по темам (архитектура, клиенты, безопасность) |
| `client-configs/` | Готовые конфиги split routing для iOS, Android, Windows |
| `cloudflare-worker/` | Cloudflare Worker для CDN-фронтинга (backup) |
| `quick-rebuild.sh` | Полная установка VPN с нуля на чистый VPS |
| `deploy-relay.sh` | Деплой relay на generic RU VPS (Timeweb/VDSina/Selectel) |
| `deploy-relay-sweden.sh` | Создание xHTTP inbound на основном VPS для relay-цепочки |
| `deploy-olcrtc-server.sh` | Установка WebRTC-сервера (аварийный) |
| `deploy-sni-split.sh` | Опциональный Layer 0.5: свой домен + nginx ssl_preread SNI-split (по рецепту @ice938) |
| `check-ip-leaks.sh` | Верификация серверного блока IP-leak эндпоинтов — запускать с клиента через активный VPN |
| `ssh_exec.py` | Утилита для управления сервером по SSH |
| `.env.example` | Шаблон конфигурации -- скопировать в `.env` и заполнить |

## Стоимость

| Статья | Стоимость | Обязательно? |
|--------|-----------|-------------|
| VPS за рубежом | ~$2/мес | Да |
| Домен | ~$6/год (первый год ~$3) | Нет (для Cloudflare backup и Layer 0.5 SNI-split) |
| Cloudflare | Бесплатно | Нет |
| RU relay VPS (Timeweb/VDSina) | ~80-100 RUB/мес (~$1) | Нет (если нужно обойти белые списки на мобильной сети) |
| **Итого минимум** | **~$2/мес** | |
| **Итого максимум** | **~$5/мес** | |

## Ссылки
[Видео на ютуб](https://youtu.be/WwX2HC3xry4)

[ТГ канал про ИИ и создание айти продуктов](https://t.me/create_products)

[Чат для обсуждений](https://t.me/create_products_chat) 

## Лицензия

[MIT](LICENSE)
