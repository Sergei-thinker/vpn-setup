# VPN для обхода блокировок в России

> **English:** Multi-layer VPN system (VLESS Reality + Yandex Cloud Relay + WebRTC) for bypassing Russian internet censorship (ТСПУ/DPI). Designed to be deployed automatically via [Claude Code](https://claude.ai/claude-code). See below for Russian documentation.

---

## Что это

VPN-инфраструктура на базе **VLESS Reality** -- протокола, который маскирует VPN-трафик под обычные HTTPS-запросы к Microsoft, Google и Apple. Для систем блокировки (ТСПУ/DPI) ваш трафик выглядит как обычный интернет-сёрфинг.

Если один метод подключения блокируют -- система автоматически переключается на следующий.

**Split routing:** российские сайты (банки, Госуслуги, VK, Yandex) идут напрямую, без VPN -- они работают быстрее и не вызывают подозрений.

## Как это работает

```
Приоритет подключения:

Layer 0: VLESS Reality        → VPS за рубежом → Интернет     ← основной
Layer 1: Yandex Cloud Relay   → VPS за рубежом → Интернет     ← обход белых списков
Layer 2: WebRTC / Телемост    → VPS за рубежом → Интернет     ← аварийный
Layer 3: Cloudflare CDN       → VPS за рубежом → Интернет     ← backup для Wi-Fi
```

| Layer | Метод | Когда нужен | Платформы |
|-------|-------|-------------|-----------|
| **0** | **VLESS Reality** | Всегда, основной вариант | Все |
| **1** | **Yandex Cloud Relay** | Мобильная сеть с белыми списками, IP VPS заблокирован | Все |
| **2** | **WebRTC / Телемост** | Полная блокировка, ничего не работает | Пока только десктоп (мобильное приложение OlcRTC ещё не создано) |
| **3** | **Cloudflare CDN** | Backup при блокировке IP VPS (только домашний Wi-Fi, т.к. Cloudflare блокируется ТСПУ с 2025) | Все |

## Что нужно сделать вам

### 1. Арендовать VPS (~$2/мес)

VPS -- это виртуальный сервер за рубежом, через который будет идти ваш трафик.

- **Пример:** [Aeza.net](https://aeza.net/) -- Швеция, Debian 12, 1.99 EUR/мес
- **Альтернативы:** 4VPS, Fornex, UFO.Hosting -- любой VPS в Европе поближе к России (Швеция, Финляндия, Германия, Нидерланды) с Debian 12
- **НЕ рекомендуется:** Hetzner, OVH, DigitalOcean -- их подсети массово заблокированы в РФ
- **Что понадобится:** IP-адрес сервера и SSH-доступ (пароль или ключ)

### 2. Купить домен *(опционально)* (~$6/год, первый год ~$3)

Домен нужен для CDN-фронтинга через Cloudflare (backup). Без домена основной VPN и Yandex Cloud relay будут работать -- этого достаточно для большинства случаев.

- **Где:** [namecheap.com](https://www.namecheap.com/)
- **Какой:** любой дешёвый домен (`.top`, `.xyz`, `.site`)

### 3. Установить VPN-клиент на устройства

| Платформа | Приложение | Цена | Где скачать |
|-----------|-----------|------|-------------|
| Windows | [Hiddify](https://hiddify.com/) | Бесплатно | GitHub / hiddify.com |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG) / [Hiddify](https://hiddify.com/) | Бесплатно | Google Play / GitHub |
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) | $2.99 | App Store |
| iOS | [v2rayU](https://apps.apple.com/app/v2rayu/id1467969912) | Бесплатно | App Store (ограниченная функциональность) |
| macOS | [Hiddify](https://hiddify.com/) | Бесплатно | GitHub / hiddify.com |

> **Почему Shadowrocket лучше на iOS?** Shadowrocket поддерживает WebSocket-транспорт, split routing и auto-select серверов. Бесплатные клиенты (v2rayU) работают для базового VLESS Reality, но не поддерживают продвинутые функции (CDN через WebSocket, автопереключение между серверами).

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
| `deploy-relay-yc.sh` | Деплой relay через Yandex Cloud |
| `deploy-olcrtc-server.sh` | Установка WebRTC-сервера (аварийный) |
| `ssh_exec.py` | Утилита для управления сервером по SSH |
| `.env.example` | Шаблон конфигурации -- скопировать в `.env` и заполнить |

## Стоимость

| Статья | Стоимость | Обязательно? |
|--------|-----------|-------------|
| VPS за рубежом | ~$2/мес | Да |
| Домен | ~$6/год (первый год ~$3) | Нет (для Cloudflare backup) |
| Cloudflare | Бесплатно | Нет |
| Yandex Cloud relay | ~400 RUB/мес (~$4) | Нет (для обхода белых списков) |
| **Итого минимум** | **~$2/мес** | |
| **Итого максимум** | **~$8/мес** | |

## Лицензия

[MIT](LICENSE)
