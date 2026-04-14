# Свой VPN для обхода блокировок в России -- полное руководство

> **4-уровневая система на базе VLESS Reality + Cloudflare CDN + Yandex Cloud Relay + WebRTC.**
> Пошаговая инструкция от нуля до полностью рабочего VPN за ~2 EUR/мес.

**Для кого:** для людей с базовыми навыками Linux (умеете подключиться по SSH и выполнять команды в терминале). Никакого опыта с VPN-протоколами не требуется -- всё объясняется с нуля.

**Актуальность:** апрель 2026. Протоколы и методы обхода адаптированы к текущему состоянию ТСПУ/DPI в России.

---

## Содержание

1. [Зачем это нужно](#1-зачем-это-нужно)
2. [Обзор архитектуры](#2-обзор-архитектуры)
3. [Что понадобится](#3-что-понадобится)
4. [Layer 0: Базовый VLESS Reality](#4-layer-0-базовый-vless-reality)
5. [Layer 1: Cloudflare CDN (Domain Fronting)](#5-layer-1-cloudflare-cdn-domain-fronting)
6. [Layer 2: Relay через российский VPS](#6-layer-2-relay-через-российский-vps)
7. [Layer 3: WebRTC через Яндекс.Телемост (аварийный)](#7-layer-3-webrtc-через-яндекстелемост-аварийный)
8. [Настройка клиентов](#8-настройка-клиентов)
9. [Обслуживание и troubleshooting](#9-обслуживание-и-troubleshooting)
10. [Безопасность](#10-безопасность)
11. [FAQ](#11-faq)
12. [Полезные ссылки](#12-полезные-ссылки)

---

## 1. Зачем это нужно

### Что такое ТСПУ

ТСПУ (технические средства противодействия угрозам) -- это оборудование, которое РКН (Роскомнадзор) устанавливает у каждого интернет-провайдера в России. По сути это "чёрные ящики", через которые проходит **весь** ваш интернет-трафик.

ТСПУ используют технологию **DPI (Deep Packet Inspection)** -- глубокий анализ пакетов. DPI смотрит не только куда вы подключаетесь (IP-адрес), но и **как** выглядит ваш трафик:

| Метод блокировки | Что анализирует | Пример |
|------------------|-----------------|--------|
| По IP-адресу | Адрес назначения | Блокировка всех IP Telegram |
| По сигнатуре протокола | Первые байты соединения | Распознавание OpenVPN, WireGuard |
| По поведению | Паттерны: объём, частота, тип | "Подозрительно много TLS-сессий" |
| Замедление | Целевое снижение скорости | YouTube: throttling до 144p |
| Заморозка сессий | TCP-сессии >15-20 КБ | Обрыв загрузки через VPN |

К апрелю 2026 заблокировано **469+ VPN-сервисов**. Домашние провайдеры (Wi-Fi) блокируют мягче, мобильные операторы (МТС, Мегафон, Yota, Tele2, Beeline) -- **значительно агрессивнее**.

### Почему обычные VPN больше не работают

| Протокол | Статус в России (2026) | Причина |
|----------|----------------------|---------|
| OpenVPN | Полностью заблокирован | Узнаваемая сигнатура |
| WireGuard | Полностью заблокирован | Распознаётся по UDP-структуре |
| Shadowsocks (старый) | Частично блокируется | Детектируется по паттернам |
| MTProto (Telegram) | Массово банится по IP | Известные подсети |
| Коммерческие VPN | Заблокировано 469+ | Узнаваемый профиль трафика |

### Почему VLESS Reality -- лучший выбор

**VLESS Reality** -- протокол, который делает VPN-трафик **неотличимым от обычного HTTPS-соединения** к крупному сайту (Microsoft, Google, Apple).

Как это работает:
1. Клиент устанавливает TLS-соединение с вашим сервером
2. Для DPI это выглядит как браузер, заходящий на `www.microsoft.com`
3. Reality подставляет реальный сертификат целевого сайта при проверке
4. Внутри TLS-туннеля идёт ваш трафик по протоколу VLESS

DPI видит: "Пользователь подключается к Microsoft по HTTPS". Реальность: трафик идёт через ваш VPN-сервер.

### Почему нужна многоуровневая защита

Даже VLESS Reality можно заблокировать -- например, заблокировав IP вашего VPS целиком. Поэтому нужна система из нескольких уровней, где каждый следующий активируется, когда предыдущий перестаёт работать. Это как запасные выходы из здания -- если один заблокирован, используете другой.

---

## 2. Обзор архитектуры

### 4 уровня защиты

```
+---------------------------------------------------------------------+
|                   МНОГОУРОВНЕВАЯ АРХИТЕКТУРА                         |
+---------------------------------------------------------------------+
|                                                                     |
|  Layer 0: ПРЯМОЕ ПОДКЛЮЧЕНИЕ (основной)                             |
|  +----------+   VLESS Reality (443/8443/2053)   +----------+        |
|  |Устройство| --------------------------------> | VPS SWE  |->Net   |
|  +----------+   Маскировка: HTTPS к Microsoft   +----------+        |
|                              Google, Apple                          |
|                                                                     |
|  Layer 1: CDN-ФРОНТИНГ ЧЕРЕЗ CLOUDFLARE                            |
|  +----------+   HTTPS/WSS    +-----------+      +----------+       |
|  |Устройство| -------------> | Cloudflare| ---> | VPS SWE  |->Net  |
|  +----------+  SNI: CF домен |  CDN      |      +----------+       |
|                              +-----------+                          |
|  ⚠ CF блокируется ТСПУ с 2025! Работает только на домашнем Wi-Fi.  |
|                                                                     |
|  Layer 2: RELAY ЧЕРЕЗ YANDEX CLOUD (рекомендуемый для мобильных)    |
|  +----------+  VLESS  +----------+  xHTTP  +----------+            |
|  |Устройство| ------> |YC VM(РФ) | ------> | VPS SWE  |->Net      |
|  +----------+         |SNI:ya.ru |          +----------+            |
|                       +----------+                                  |
|  IP Yandex Cloud в белых списках ТСПУ! Обходит белые списки.        |
|                                                                     |
|  Layer 3: АВАРИЙНЫЙ -- WebRTC ЧЕРЕЗ ЯНДЕКС.ТЕЛЕМОСТ                 |
|  +----------+  WebRTC  +-----------+  DataCh  +----------+         |
|  |Устройство| -------> |Я.Телемост | -------> | VPS SWE  |->Net   |
|  +----------+          |   (SFU)   |           +----------+         |
|                        +-----------+                                |
|  Яндекс ВСЕГДА в белом списке. До 44 Mbps.                         |
|                                                                     |
|  + SPLIT ROUTING: Российские сайты идут НАПРЯМУЮ                    |
|    (Yandex, VK, Госуслуги, банки -- без VPN)                        |
|                                                                     |
+---------------------------------------------------------------------+
```

### Таблица уровней

| Layer | Метод | Когда нужен | Сложность | Стоимость |
|-------|-------|-------------|-----------|-----------|
| 0 | VLESS Reality (прямое подключение) | Всегда, основной вариант | Средняя | ~2 EUR/мес |
| 1 | Cloudflare CDN (WebSocket) | VPS IP заблокирован (только Wi-Fi!) | Средняя | +1 EUR/год (домен) |
| 2 | Relay через Yandex Cloud | **Белые списки на мобильной сети** | Средняя | +~400 RUB/мес (~4 EUR) |
| 3 | WebRTC через Яндекс.Телемост | Полный white-list, всё заблокировано | Высокая | Бесплатно |

> **Обновление (апрель 2026):** Cloudflare **активно блокируется ТСПУ с середины 2025**. Layer 1 работает только на домашнем Wi-Fi. Для мобильной сети с белыми списками используйте **Layer 2 (Yandex Cloud)** -- IP Yandex Cloud подтверждённо в белых списках.

### Приоритет подключения (auto-select)

Клиенты (Hiddify, Shadowrocket, v2rayNG) умеют автоматически проверять доступность серверов и переключаться на рабочий:

1. `reality-main:443` -- основной (минимальная задержка)
2. `reality-google:8443` -- если 443 заблокирован
3. `reality-apple:2053` -- ещё один резервный SNI
4. `ws-cloudflare` через Cloudflare CDN -- если IP VPS заблокирован (только Wi-Fi!)
5. **YC-Relay** через Yandex Cloud -- **при белых списках на мобильной сети**
6. WebRTC через Яндекс.Телемост -- последний рубеж

---

## 3. Что понадобится

### Бюджет

| Статья | Стоимость | Обязательно? |
|--------|-----------|-------------|
| VPS за рубежом | ~2 EUR/мес | Да |
| Домен (для CDN) | ~1 EUR/год | Рекомендуется |
| Cloudflare аккаунт | Бесплатно | Рекомендуется |
| Shadowrocket (iOS) | $2.99 разово | Только для iOS |
| Yandex Cloud relay (preemptible) | ~400 RUB/мес (~4 EUR) | Для обхода белых списков |
| **Итого минимум** | **~2 EUR/мес** | |
| **Итого максимум** | **~8 EUR/мес** | |

### Базовые навыки

- Подключение по SSH (PuTTY на Windows или терминал на Mac/Linux)
- Выполнение команд в командной строке Linux
- Копирование/вставка текста (будет много copy-paste)

### Список необходимого

**1. VPS (виртуальный сервер) за рубежом**

Рекомендуемые провайдеры:

| Провайдер | Цена | Плюсы | Минусы |
|-----------|------|-------|--------|
| **AlphaVPS** (alphavps.com) | от €3.50/мес | KVM, Болгария (вне 14 Eyes), свои серверы | -- |
| **RackNerd** (racknerd.com) | от ~$1/мес | Самый дешёвый, EU-локации (Амстердам, Страсбург) | US-компания |
| **Hetzner** (hetzner.com) | от €3.49/мес | Мощный за копейки, ДЦ в Финляндии | IP могут блокироваться ТСПУ |
| **Netcup** (netcup.com) | от €3.99/мес | Transparency reports, борются за приватность в суде | -- |

> **⛔ НЕ используйте российские хостинги:** Aeza, VDSina, REG.RU, Timeweb — подчиняются Роскомнадзору, могут блокировать VPN по ФЗ-236.
> **⚠️ Осторожно:** Hetzner, OVH, DigitalOcean — их подсети массово заблокированы ТСПУ (но свежий IP может работать).

Минимальные требования к VPS: 1 CPU, 512 MB RAM, Debian 12. Рекомендуемая локация: Швеция или Нидерланды (пинг из РФ ~50-70 мс).

**2. Домен (для Layer 1 -- CDN)**

Любой дешёвый домен. Namecheap -- от ~1 EUR/год. Домен нужен для Cloudflare CDN-фронтинга.

**3. Клиенты**

| Платформа | Клиент | Стоимость |
|-----------|--------|-----------|
| Windows | Hiddify | Бесплатно |
| iOS | Shadowrocket (лучший) | $2.99 |
| iOS | v2RayTun (альтернатива) | Бесплатно |
| Android | v2rayNG | Бесплатно |
| macOS/Linux | Hiddify или nekoray | Бесплатно |

**4. Аккаунт Cloudflare** (бесплатно) -- cloudflare.com

---

## 4. Layer 0: Базовый VLESS Reality

Это основной уровень. После выполнения этого раздела у вас будет полностью рабочий VPN.

### 4.1. Аренда VPS

Рассмотрим на примере AlphaVPS (надёжный EU-провайдер):

1. Зайдите на [alphavps.com](https://alphavps.com/) (или другой провайдер из таблицы выше)
2. Зарегистрируйтесь, оплатите (карта, PayPal)
3. Создайте сервер:
   - Тип: **KVM** (не OpenVZ!)
   - Локация: **Нюрнберг** (Германия) или **Амстердам** (Нидерланды)
   - ОС: **Debian 12**
   - Оплата: почасовая (можно удалить и пересоздать если IP заблокируют)
4. Запишите:
   - **IP-адрес** сервера
   - **root-пароль** (придёт на email или отобразится в панели)

> **Совет:** если при проверке IP окажется что он уже заблокирован -- удалите сервер и создайте новый. При почасовой оплате это стоит копейки.

### 4.2. Базовая настройка VPS

Подключитесь к серверу по SSH:

```bash
ssh root@<ВАШ_IP>
```

Если вы на Windows и не имеете SSH-клиента -- скачайте [PuTTY](https://www.putty.org/) или используйте Windows Terminal (встроен в Windows 10/11).

**Обновите систему:**

```bash
apt update && apt upgrade -y
```

**Смените SSH-порт** (порт 22 блокируется ТСПУ для некоторых зарубежных IP):

```bash
nano /etc/ssh/sshd_config
```

Найдите строку `#Port 22` и замените на:

```
Port 49152
```

> Выберите любой порт от 10000 до 65535. Запомните его -- без него не подключитесь!

Сохраните (`Ctrl+O`, `Enter`, `Ctrl+X`) и перезапустите SSH:

```bash
systemctl restart sshd
```

Теперь подключайтесь так:

```bash
ssh -p 49152 root@<ВАШ_IP>
```

### 4.3. Установка 3X-UI

3X-UI -- это веб-панель для управления Xray-core (движок VLESS Reality). Она позволяет настраивать VPN через браузер, без ручного редактирования конфигов.

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

Скрипт спросит:

1. **Panel Port** -- введите `y`, затем порт панели (например, `54321`). Запишите его!
2. **Username / Password** -- логин и пароль для веб-панели. **Используйте сложные!**
3. **SSL Certificate** -- выберите опцию `2` (Let's Encrypt for IP Address)
4. **IPv6** -- пропустите (Enter)
5. **ACME port** -- оставьте 80 (Enter)

После установки скрипт выдаст URL панели вида:

```
https://<ВАШ_IP>:<ПОРТ_ПАНЕЛИ>/<СЛУЧАЙНЫЙ_ПУТЬ>/
```

> **Запишите этот URL, логин и пароль!** Без них вы не сможете управлять VPN.

Полезные команды управления панелью:

```bash
x-ui start          # Запуск
x-ui stop           # Остановка
x-ui restart        # Перезапуск
x-ui status         # Статус
x-ui settings       # Текущие настройки (порт, URL)
```

### 4.4. Создание VLESS Reality inbound

Откройте URL панели в браузере и войдите.

1. Перейдите в **Inbounds** -> **+ Add Inbound**
2. Заполните форму:

| Поле | Значение | Пояснение |
|------|----------|-----------|
| Enabled | Включено | -- |
| Remark | `reality-main` | Любое имя для себя |
| Protocol | `vless` | -- |
| Port | `443` | Стандартный HTTPS-порт |
| Transmission | `TCP (RAW)` | -- |
| Security | `Reality` | Включает маскировку |
| uTLS | `chrome` | Имитирует браузер Chrome |
| Target (Dest) | `www.microsoft.com:443` | Сайт для маскировки |
| SNI | `www.microsoft.com` | Домен в Server Name Indication |

3. Раскройте секцию **Client**:
   - **Flow:** оставьте **пустым**

> **Почему flow пустой:** в некоторых версиях Xray-core `xtls-rprx-vision` вызывает краш (panic XtlsPadding). Без flow всё работает стабильно. Если у вас Xray >= 25.12.8 и вы хотите попробовать -- можно включить `xtls-rprx-vision`, но при проблемах отключите обратно.

4. Нажмите **"Get New Cert"** -- сгенерируются Public Key и Private Key
5. Нажмите **Create**

**Создайте резервные inbound-ы** (разные порты и SNI -- на случай блокировки):

| Remark | Port | SNI/Target | Зачем |
|--------|------|-----------|-------|
| `reality-google` | 8443 | `dl.google.com` | Если 443 заблокирован |
| `reality-apple` | 2053 | `www.apple.com` | Ещё один резервный |

Настройки аналогичны основному inbound, меняется только порт и SNI/Target.

**Получение VLESS-ссылки:**
- В списке Inbounds нажмите `...` -> **QR Code** или **Export Link**
- Ссылка выглядит как: `vless://<UUID>@<IP>:443?...`
- Эту ссылку вы импортируете в клиент (раздел 8)

### 4.5. BBR и TCP-тюнинг

BBR -- алгоритм управления перегрузками от Google. **Критически важен для мобильных сетей** -- без него скорость может быть в 2-3 раза ниже.

Откройте файл:

```bash
nano /etc/sysctl.conf
```

Добавьте в конец:

```ini
# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP keepalive (не даёт соединению "умереть")
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Увеличенные буферы (для высокоскоростных соединений)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Дополнительные оптимизации
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 4096
net.ipv4.tcp_slow_start_after_idle = 0
```

Примените:

```bash
sysctl -p
```

Проверьте что BBR активен:

```bash
sysctl net.ipv4.tcp_congestion_control
```

Должно вывести: `net.ipv4.tcp_congestion_control = bbr`

### 4.6. Файрвол (UFW)

```bash
apt install ufw -y

# Разрешите нужные порты
ufw allow 49152    # ваш SSH-порт (замените на свой!)
ufw allow 80       # для Let's Encrypt
ufw allow 443      # для VLESS Reality (основной)
ufw allow 8443     # для VLESS Reality (резервный)
ufw allow 2053     # для VLESS Reality (резервный)
ufw allow 54321    # порт панели 3X-UI (замените на свой!)

# Включите файрвол
ufw enable
```

> **Внимание:** убедитесь, что вы добавили свой SSH-порт в разрешённые ПЕРЕД включением UFW. Иначе потеряете доступ к серверу!

**Установите fail2ban** (защита от перебора паролей):

```bash
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban
```

### 4.7. DNS на сервере

```bash
apt install systemd-resolved -y
```

Отредактируйте `/etc/systemd/resolved.conf`:

```bash
nano /etc/systemd/resolved.conf
```

Замените содержимое секции `[Resolve]`:

```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 8.8.4.4
DNSOverTLS=yes
```

Перезапустите:

```bash
systemctl restart systemd-resolved
```

В 3X-UI -> **Xray Settings** -> **DNS**, вставьте:

```json
{"dns":{"servers":["https+local://1.1.1.1/dns-query"],"queryStrategy":"UseIPv4"}}
```

### 4.8. Мониторинг (автоперезапуск Xray)

Создайте скрипт:

```bash
nano /root/monitor-xray.sh
```

Содержимое:

```bash
#!/bin/bash
if ! pgrep -x xray > /dev/null; then
    x-ui restart
    echo "$(date): Xray restarted" >> /var/log/xray-monitor.log
fi
```

Сделайте исполняемым и добавьте в cron:

```bash
chmod +x /root/monitor-xray.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/monitor-xray.sh") | crontab -
```

Теперь каждые 5 минут скрипт проверяет, работает ли Xray, и перезапускает если нет.

### 4.9. Тестирование

1. Получите VLESS-ссылку из панели 3X-UI (раздел 4.4)
2. Настройте клиент (см. раздел 8)
3. Подключитесь
4. Зайдите на [2ip.ru](https://2ip.ru/) -- должен показать IP вашего VPS (Швеция)
5. Зайдите на YouTube -- должен работать без ограничений

> **Если не работает:** см. раздел 9 "Troubleshooting"

---

## 5. Layer 1: Cloudflare CDN (Domain Fronting)

### 5.1. Зачем нужен CDN

> **Важное обновление (апрель 2026):** Cloudflare **активно блокируется ТСПУ с середины 2025**. При белых списках на мобильной сети Layer 1 **не работает**. Для обхода белых списков на мобильном интернете используйте **Layer 2 (Yandex Cloud relay)**.
>
> Layer 1 остаётся полезным на **домашнем Wi-Fi**, где блокировка менее агрессивна.

Если провайдер заблокирует IP вашего VPS целиком (а не протокол), прямое подключение перестанет работать. Cloudflare CDN может помочь на домашнем Wi-Fi:

```
Обычно:   Устройство ---> VPS (заблокирован!) --X--> Интернет

Через CDN: Устройство ---> Cloudflare CDN ---> VPS ---> Интернет
                           (может работать на Wi-Fi)
```

IP-адреса Cloudflare (104.16.0.0/12, 172.64.0.0/13) ранее находились в белых списках ТСПУ. С 2025 года Cloudflare блокируется, но на домашних провайдерах блокировка менее строгая.

### 5.2. Покупка домена

1. Зайдите на [Namecheap](https://www.namecheap.com/) (или любой другой регистратор)
2. Купите самый дешёвый домен (~1 EUR/год). Например: `mysite123.top`
3. Зона `.top`, `.xyz`, `.click` -- самые дешёвые

### 5.3. Настройка Cloudflare

1. Зарегистрируйтесь на [cloudflare.com](https://cloudflare.com/)
2. Нажмите **Add a Site** -> введите ваш домен
3. Выберите план **Free**
4. Cloudflare покажет свои DNS-серверы (ns1.cloudflare.com, ns2.cloudflare.com)
5. В панели регистратора (Namecheap) смените NS-серверы на серверы Cloudflare
6. Подождите 5-30 минут пока DNS обновится

**Добавьте DNS-записи в Cloudflare:**

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `@` (ваш домен) | IP вашего VPS | **Proxied (ON)** -- оранжевое облако! |
| A | `www` | IP вашего VPS | **Proxied (ON)** |

> **Важно:** Proxy должен быть **включён** (оранжевое облако). Это и есть CDN-фронтинг -- трафик идёт через Cloudflare, а не напрямую к VPS.

**Настройте SSL/TLS:**
- В Cloudflare -> **SSL/TLS** -> **Overview** -> выберите **Full**

### 5.4. Создание WebSocket inbound на VPS

В 3X-UI создайте **новый** inbound (не меняйте существующие!):

| Поле | Значение | Пояснение |
|------|----------|-----------|
| Remark | `ws-cloudflare` | Для CDN |
| Protocol | `vless` | -- |
| Port | `2082` | Не 443 -- он уже занят Reality! |
| Transmission | **WebSocket** | Cloudflare поддерживает WS |
| Path | `/ws-vless-<СЛУЧАЙНАЯ_СТРОКА>` | Длинная случайная строка! |
| Security | **none** | TLS обеспечивает Cloudflare, не дублируйте |

> **Почему порт 2082?** Порт 443 занят основным VLESS Reality. Cloudflare поддерживает WebSocket-проксирование на несколько портов (80, 2082, 2086, 8080 и др.).

> **Почему Security: none?** Cloudflare уже обеспечивает TLS-шифрование между клиентом и CDN, а также между CDN и вашим VPS (при SSL/TLS: Full). Двойное шифрование не нужно.

Запишите **Path** (например `/ws-vless-x7k9m2`) -- он понадобится для Worker.

Не забудьте добавить порт 2082 в файрвол:

```bash
ufw allow 2082
```

### 5.5. Cloudflare Worker

Worker -- это код, который запускается на серверах Cloudflare и проксирует WebSocket-соединения к вашему VPS. Для обычных HTTP-запросов он показывает страницу "Coming Soon" (маскировка).

**Вариант A: Через Cloudflare Dashboard (проще)**

1. В Cloudflare -> **Workers & Pages** -> **Create Application** -> **Create Worker**
2. Дайте имя (например `vpn-ws-proxy`)
3. Нажмите **Deploy** (с дефолтным кодом)
4. Нажмите **Edit Code** и замените содержимое на:

```javascript
const LANDING_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Site Under Construction</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen,Ubuntu,sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;
         background:#f5f5f5;color:#333}
    .container{text-align:center;padding:2rem}
    h1{font-size:2rem;margin-bottom:.5rem}
    p{color:#666;margin-bottom:1.5rem}
    .bar{width:200px;height:4px;background:#ddd;border-radius:2px;margin:0 auto;overflow:hidden}
    .bar span{display:block;width:40%;height:100%;background:#4a90d9;border-radius:2px;
              animation:slide 1.5s ease-in-out infinite}
    @keyframes slide{0%{transform:translateX(-100%)}100%{transform:translateX(350%)}}
    footer{margin-top:2rem;font-size:.75rem;color:#aaa}
  </style>
</head>
<body>
  <div class="container">
    <h1>Coming Soon</h1>
    <p>We are working hard to bring you something amazing. Stay tuned!</p>
    <div class="bar"><span></span></div>
    <footer>&copy; 2024 All rights reserved.</footer>
  </div>
</body>
</html>`;

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      const secretPath = env.WS_PATH || '/ws-proxy';

      // Только проксируем на секретном пути
      if (url.pathname !== secretPath) {
        return landingPage();
      }

      // Требуем WebSocket upgrade
      const upgradeHeader = request.headers.get('Upgrade');
      if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
        return new Response('Expected Upgrade: websocket', { status: 426 });
      }

      // Строим URL бэкенда
      const backendHost = env.BACKEND_HOST || '<ВАШ_VPS_IP>';
      const backendPort = env.BACKEND_PORT || '2082';

      const backendUrl = new URL(request.url);
      backendUrl.hostname = backendHost;
      backendUrl.port = backendPort;
      backendUrl.protocol = 'http:';

      // Проксируем запрос к бэкенду
      const backendRequest = new Request(backendUrl.toString(), {
        method: request.method,
        headers: request.headers,
        body: request.body,
      });

      return await fetch(backendRequest);
    } catch (err) {
      console.error('Worker error:', err);
      return landingPage(500);
    }
  },
};

function landingPage(status = 200) {
  return new Response(LANDING_HTML, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}
```

5. Нажмите **Save and Deploy**

6. Настройте переменные окружения: **Settings** -> **Variables**:

| Variable | Value |
|----------|-------|
| `BACKEND_HOST` | IP вашего VPS |
| `BACKEND_PORT` | `2082` |
| `WS_PATH` | `/ws-vless-<ВАША_СЛУЧАЙНАЯ_СТРОКА>` |

7. Настройте route: **Triggers** -> **Routes** -> **Add Route**:
   - Route: `ваш-домен.top/*`
   - Zone: ваш домен

**Вариант B: Через Wrangler CLI (для продвинутых)**

Создайте файл `wrangler.toml`:

```toml
name = "vpn-ws-proxy"
main = "worker.js"
compatibility_date = "2024-09-23"

[vars]
BACKEND_HOST = "<ВАШ_VPS_IP>"
BACKEND_PORT = "2082"
WS_PATH = "/ws-vless-<СЛУЧАЙНАЯ_СТРОКА>"
```

Задеплойте:

```bash
CLOUDFLARE_API_TOKEN=<ВАШ_ТОКЕН> npx wrangler deploy
```

### 5.6. Тестирование Layer 1

Настройте клиент с параметрами CDN-пути:

| Поле | Значение |
|------|----------|
| Protocol | VLESS |
| Address | `ваш-домен.top` (НЕ IP!) |
| Port | 443 |
| UUID | (из панели 3X-UI, тот же что в ws-cloudflare inbound) |
| Transport | **WebSocket** |
| Path | `/ws-vless-<ВАША_СТРОКА>` |
| TLS | **ON** |
| SNI | `ваш-домен.top` |
| Flow | пусто |

Подключитесь и проверьте на [2ip.ru](https://2ip.ru/) -- должен показать IP VPS (не Cloudflare).

> **Запасной вариант:** если домен заблокируют, можно подключаться через адрес Workers: `vpn-ws-proxy.<ваш-аккаунт>.workers.dev` -- SNI будет показывать `workers.dev` (домен Cloudflare), что ещё сложнее заблокировать.

---

## 6. Layer 2: Relay через Yandex Cloud

### 6.1. Зачем нужен relay

Когда мобильные операторы (МТС, Мегафон, Tele2, Beeline) включают **белые списки**, пропускается только трафик к российским IP. Cloudflare тоже блокируется с 2025 года. Relay через Yandex Cloud решает эту проблему:

```
Устройство --> Yandex Cloud VM (IP в белом списке!) --> VPS Швеция --> Интернет
               VLESS Reality (SNI: yandex.ru)           xHTTP relay
               Порт 15443 + nginx декой на 80/443
```

**Почему Yandex Cloud:** IP Yandex Cloud **подтверждённо в белых списках** ТСПУ (добавлен 19.09.2025). Яндекс -- стратегический актив РФ, его IP не заблокируют.

### 6.2. Что понадобится

| Компонент | Стоимость | Комментарий |
|-----------|-----------|-------------|
| Аккаунт Yandex Cloud | Бесплатно | cloud.yandex.ru |
| Preemptible VM (2 core, 2GB) | ~400 RUB/мес (~4 EUR) | Останавливается каждые 24ч |
| Non-preemptible VM (опц.) | ~1800 RUB/мес (~18 EUR) | Работает постоянно |
| Egress трафик < 100 GB | Бесплатно | Хватает для 1-2 пользователей |
| `yc` CLI | Бесплатно | Утилита командной строки |

<details>
<summary><strong>Откуда берётся цена ~400-500₽? (на сайте YC от 1700₽!)</strong></summary>

На сайте Yandex Cloud показывают цену за **обычную VM с полной мощностью**. Мы используем два трюка:

**1. Прерываемая VM (preemptible)** — в ~3 раза дешевле обычной. Минус: Яндекс может перезапустить её раз в сутки. Для relay-прокси это не проблема — скрипт `rotate-relay-yc.sh` сам поднимает VM обратно.

**2. 20% мощности CPU (core-fraction 20)** — платим за пятую часть процессора. Relay просто перекидывает трафик, ему не нужна полная мощность.

Разбивка по статьям (данные из реального биллинга, апрель 2026):

| Статья | В месяц |
|--------|---------|
| CPU (2 ядра × 20%, preemptible) | ~222 ₽ |
| RAM (2 ГБ, preemptible) | ~111 ₽ |
| Публичный IP (динамический) | ~100-190 ₽ |
| Диск HDD (10 ГБ) | ~32 ₽ |
| Трафик (до 100 ГБ) | бесплатно |
| **Итого** | **~430-550 ₽** |

> **Важно:** основные расходы — аренда VM, а не трафик. Даже если пользоваться VPN в 10 раз активнее, цена почти не изменится. Трафик бесплатен до 100 ГБ/мес — этого хватает для обычного использования.

При создании VM выбирайте: **Прерываемая → да**, **Гарантированная доля vCPU → 20%**. Тогда цена будет ~400-500₽, а не 1700₽.

</details>

### 6.3. Подготовка шведского VPS (принимающая сторона)

На шведском VPS нужно создать inbound для приёма relay-трафика.

**Автоматический способ (рекомендуемый):**

```bash
# Скрипт создаст xHTTP Reality inbound на порту 10443
python ssh_exec.py deploy deploy-relay-sweden.sh
```

**Или вручную** -- в 3X-UI создайте новый inbound:

| Поле | Значение |
|------|----------|
| Remark | `relay-xhttp` |
| Protocol | `vless` |
| Port | `10443` |
| Transmission | **xHTTP** |
| xHTTP Mode | `auto` |
| Security | **Reality** |
| Target | `www.microsoft.com:443` |
| SNI | `www.microsoft.com` |

Откройте порт и запишите credentials:

```bash
ufw allow 10443
```

Запишите:
- UUID клиента
- Public Key
- Short ID

### 6.4. Установка yc CLI

```bash
# Linux/macOS
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

# Windows (скачать вручную)
# Узнайте версию:
curl -s https://storage.yandexcloud.net/yandexcloud-yc/release/stable
# Скачайте: https://storage.yandexcloud.net/yandexcloud-yc/release/<VERSION>/windows/amd64/yc.exe
```

Настройте:

```bash
yc init
# 1. Перейдите по ссылке OAuth, скопируйте токен
# 2. Выберите облако и folder
# 3. Выберите зону (ru-central1-a)
```

### 6.5. Заполните .env

```bash
# В файле .env (в корне проекта):
YC_FOLDER_ID=<ваш folder ID из yc config list>
SWEDEN_VPS_IP=<IP шведского VPS>
SWEDEN_RELAY_PORT=10443
SWEDEN_RELAY_UUID=<UUID из шага 6.3>
SWEDEN_RELAY_PUBKEY=<Public Key из шага 6.3>
SWEDEN_RELAY_SID=<Short ID из шага 6.3>
```

### 6.6. Деплой VM в Yandex Cloud

```bash
bash deploy-relay-yc.sh
```

Скрипт автоматически:
1. Создаст VPC-сеть, подсеть и security group
2. Сгенерирует x25519 ключи и UUID для relay
3. Создаст cloud-init (Xray + nginx декой + BBR)
4. Поднимет preemptible VM
5. Дождётся запуска Xray
6. Выведет **VLESS URI** для клиента
7. Сохранит credentials в `yc-relay-credentials.txt`

**Опции:**

| Флаг | Назначение |
|------|-----------|
| `--non-interactive` | Без подтверждения |
| `--no-preemptible` | Обычная VM (дороже, без рестартов) |
| `--static-ip` | Зарезервировать статический IP (+100 RUB/мес) |

### 6.7. Anti-detection (маскировка от SmartWebSecurity)

Yandex Cloud использует ML-систему SmartWebSecurity для детекции прокси. Наши меры:

| Мера | Зачем |
|------|-------|
| **Nginx декой** на 80/443 | VM выглядит как обычный веб-сервер |
| **Xray на порту 15443** (не 443) | Не конфликтует с декоем, менее подозрителен |
| **SNI: yandex.ru** | Нативный для Yandex Cloud IP (не gosuslugi.ru!) |
| **Cloud-init** | VM настраивается при создании, без SSH-скриптов |
| **Низкий трафик** | 1 пользователь, < 50 GB/мес |

### 6.8. Настройка клиента для relay

После `deploy-relay-yc.sh` вы получите VLESS URI. Импортируйте его в клиент, или настройте вручную:

| Поле | Значение |
|------|----------|
| Protocol | VLESS |
| Address | IP Yandex Cloud VM |
| Port | **15443** |
| UUID | (из yc-relay-credentials.txt) |
| Transport | TCP |
| Security | Reality |
| SNI | **yandex.ru** |
| Fingerprint | `chrome` |
| Public Key | (из yc-relay-credentials.txt) |
| Short ID | (из yc-relay-credentials.txt) |
| Flow | пусто |

### 6.9. Preemptible VM: авто-рестарт

Preemptible VM останавливается каждые 24 часа. **IP может измениться при рестарте.**

Настройте авто-рестарт:

```bash
# Добавьте в cron (на шведском VPS или локальной машине):
crontab -e
# Добавьте строку:
*/5 * * * * /path/to/rotate-relay-yc.sh --cron >> /var/log/yc-relay-rotate.log 2>&1
```

`rotate-relay-yc.sh` автоматически:
- Проверяет статус VM каждые 5 минут
- Перезапускает если STOPPED
- Обновляет `.env` и `yc-relay-credentials.txt` если IP изменился
- Выводит новый VLESS URI

> **Если IP меняется слишком часто** -- используйте `--static-ip` при деплое (+100 RUB/мес) или `--no-preemptible` (~1800 RUB/мес).

### 6.10. Тестирование

1. Добавьте VLESS URI в клиент (Hiddify/Shadowrocket/v2rayNG)
2. Подключитесь через профиль `YC-Relay`
3. Зайдите на [2ip.ru](https://2ip.ru/) -- должен показать IP **шведского** VPS (не российского!)
4. Проверьте декой: `http://<YC_IP>/health` -- должен ответить `ok`

### 6.11. Мониторинг и управление

```bash
python ssh_exec.py yc-status             # Статус VM (без SSH, через yc CLI)
python ssh_exec.py -t relay status       # Статус Xray через SSH
python ssh_exec.py -t relay logs         # Логи Xray
bash rotate-relay-yc.sh                  # Ручной рестарт если STOPPED
bash monitor-relay.sh                    # Полный health check обоих VPS
```

### 6.12. Fallback (если Yandex Cloud заблокировали)

```
YC заблокировали аккаунт → deploy-relay.sh на VK Cloud или Timeweb
VK Cloud не работает      → deploy-relay.sh на VDSina или 4VPS
Всё заблокировано         → Layer 3 (WebRTC через Яндекс.Телемост)
```

Скрипт `deploy-relay.sh` разворачивает relay на generic VPS (Timeweb, VDSina) с SNI `gosuslugi.ru` на порту 443. Используйте как запасной вариант.

> **Предупреждение:** Минцифры предупредило Яндекс и VK о необходимости блокировать VPN-пользователей (дедлайн -- апрель 2026). Имейте запасного провайдера и не полагайтесь только на Yandex Cloud.

---

## 7. Layer 3: WebRTC через Яндекс.Телемост (аварийный)

### 7.1. Зачем нужен

Это последний рубеж -- когда ВСЁ остальное заблокировано (включая Cloudflare и relay). OlcRTC туннелирует данные через WebRTC DataChannel сервиса Яндекс.Телемост.

Яндекс ВСЕГДА в белом списке РКН. ТСПУ не может заблокировать трафик к Яндексу.

| Параметр | Значение |
|----------|----------|
| Пропускная способность | До 44 Mbps |
| Латентность | ~57 мс (100 байт), ~130 мс (8 КБ) |
| Протокол | DataChannel (SCTP over DTLS over ICE) |
| Платформы | **Только Linux и Windows (через WSL2)** |
| iOS/Android | **Не поддерживается** |

> **Важно:** Layer 3 работает **только на десктопе**. Для мобильных устройств Layer 2 (relay) -- последний рубеж.

### 7.2. Установка OlcRTC

Репозиторий: [github.com/zarazaex69/olcRTC](https://github.com/zarazaex69/olcRTC)

**На VPS (серверная часть):**

```bash
bash <(curl -sL zarazaex.xyz/srv.sh)
```

**На клиенте (Linux или WSL2 на Windows):**

```bash
bash <(curl -sL zarazaex.xyz/cnc.sh)
```

### 7.3. Использование

1. Создайте конференцию в Яндекс.Телемост ([telemost.yandex.ru](https://telemost.yandex.ru/))
2. Запустите серверную часть на VPS -- введите Conference ID и ключ шифрования
3. Запустите клиент -- введите те же Conference ID и ключ
4. Локальный **SOCKS5 прокси** будет доступен на `localhost:8809`

**На Windows (через WSL2):**
1. Убедитесь что WSL2 установлен: `wsl --status`
2. В WSL2 запустите клиент
3. SOCKS5 прокси на `localhost:8809`
4. В Hiddify: добавьте SOCKS5 прокси -> `127.0.0.1:8809`

**Проверка:**

```bash
curl --socks5h localhost:8809 https://ifconfig.me
```

Должен показать IP шведского VPS.

### 7.4. Ограничения Layer 3

- Только Linux и Windows (через WSL2) -- iOS и Android не поддерживаются
- Ручное создание конференций (нет автоматического reconnect)
- 8 КБ лимит на сообщение (фрагментация для больших пакетов)
- Яндекс может ограничить DataChannel в будущем
- Не маскирует трафик под реальные видеозвонки

---

## 8. Настройка клиентов

### 8.1. Windows -- Hiddify

1. Скачайте с [hiddify.com](https://hiddify.com/)
2. Скопируйте subscription-ссылку из панели 3X-UI (Inbounds -> ... -> Subscription)
3. В Hiddify нажмите **"+"** -> **"Буфер обмена"**
4. **Настройки -> Входящие -> Режим службы -> "Системный прокси"**

> **Важно:** режим "VPN" может давать ошибку "failed to start background core". Используйте **"Системный прокси"**.

5. Нажмите кнопку подключения
6. Проверьте IP на [2ip.ru](https://2ip.ru/)

**Настройка TLS-фрагментации** (для мобильных сетей и агрессивного DPI):

Настройки -> Config Options -> Fragment:

| Параметр | Значение |
|----------|----------|
| Enable | Включить |
| Mode | `tlshello` |
| Size | `100-400` |
| Interval | `1-3` ms |

> **Почему 100-400, а не 1-5?** TLS ClientHello ~ 300 байт. При 1-5 байт/фрагмент нужно 60-300 фрагментов -> +300-600 мс overhead на каждое соединение. При 100-400 байт -- 1-3 фрагмента -> 10-30 мс.

**Настройка DNS:**

| Параметр | Значение | Пояснение |
|----------|----------|-----------|
| Remote DNS | `https://1.1.1.1/dns-query` | DoH через туннель |
| Direct DNS | `https://77.88.8.8/dns-query` | Yandex DoH, работает в РФ |
| IPv6 | Отключить | Предотвращает утечки |

### 8.2. iOS -- Shadowrocket (рекомендуется)

Shadowrocket ($2.99 в App Store) -- самый быстрый iOS-клиент для VLESS. Даёт +20-40% скорости по сравнению с бесплатными альтернативами.

> **Требуется аккаунт в нероссийском App Store** (американский, казахский и т.д.)

1. Установите Shadowrocket из App Store
2. Скопируйте VLESS-ссылку из 3X-UI
3. В Shadowrocket нажмите **"+"** (ссылка импортируется автоматически из буфера обмена)
4. Включите:
   - **UDP Relay**: On (критично для YouTube/видео -- QUIC/HTTP3)
   - **Sniffing**: On
5. Проверьте IP на [2ip.ru](https://2ip.ru/) -- должен показать Швецию

**Альтернатива для iOS (бесплатно):** v2RayTun

1. Установите v2RayTun из App Store
2. Импортируйте конфиг через QR или ссылку
3. **Обязательно настройте фрагментацию:**
   - Fragment: включить
   - Packets: `tlshello`
   - Length: `100-400`
   - Interval: `1-3` ms
4. UDP Relay: включить

### 8.3. Android -- v2rayNG

1. Установите из [Google Play](https://play.google.com/store/apps/details?id=com.v2ray.ang) или [GitHub](https://github.com/2dust/v2rayNG)
2. Нажмите **"+"** -> **"Scan QR code"** (или Import from clipboard)
3. Отсканируйте QR-код из панели 3X-UI
4. Нажмите кнопку подключения
5. Проверьте IP на [2ip.ru](https://2ip.ru/)

Для добавления нескольких серверов (auto-select):
1. Добавьте все серверы (reality-main, reality-google, reality-apple, CDN)
2. Создайте **Subscription Group** с health check
3. Клиент будет автоматически выбирать рабочий сервер

### 8.4. macOS/Linux -- Hiddify или nekoray

1. Скачайте [Hiddify](https://hiddify.com/) или [nekoray](https://github.com/MatsuriDayo/nekoray)
2. Импортируйте subscription-ссылку
3. Подключитесь

### 8.5. Split routing -- российские сайты напрямую

**Зачем:** без split routing **весь** трафик идёт через Швецию. Это означает:
- Российские сайты работают медленнее (трафик летит в Стокгольм и обратно)
- Банки и Госуслуги могут блокировать шведский IP
- Яндекс и VK показывают капчи и ограничения

**Принцип:** российские домены и IP -> напрямую, всё остальное -> через VPN.

**Серверный routing (рекомендуется):**

В 3X-UI -> **Xray Settings** -> **Routing**, вставьте:

```json
{
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    {
      "type": "field",
      "outboundTag": "direct",
      "domain": ["geosite:category-ru"]
    },
    {
      "type": "field",
      "outboundTag": "direct",
      "ip": ["geoip:ru", "geoip:private"]
    }
  ]
}
```

Обновите geo-базы:

```bash
wget -O /usr/local/x-ui/bin/geosite.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget -O /usr/local/x-ui/bin/geoip.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
```

**Клиентский routing:**

*iOS (Shadowrocket):*
- Config -> Rules -> Add Rule -> DOMAIN-SUFFIX -> `yandex.ru` -> DIRECT
- Повторите для: `vk.com`, `gosuslugi.ru`, `sberbank.ru`, `tinkoff.ru` и других

*Android (v2rayNG):*
- Settings -> Routing -> Custom Rules
- Добавьте российские домены в Direct

*Windows (v2rayN — рекомендуемый):*
1. Settings → Regional Presets → **Russia**
2. Settings → **Routing Settings** → выбрать набор **"RUv1-Всё, кроме РФ"**
3. **НЕ** использовать "RUv1-Всё" — он гонит весь трафик через VPN, и российские сервисы (Rutube, Кинопоиск, банки) блокируют по иностранному IP
4. Проверка: https://2ip.ru → Россия, https://ifconfig.me → Швеция

*Windows (Hiddify):*
- Settings -> Routing -> Custom
- Добавьте домены в Direct

**Основные домены для split routing (минимальный набор):**

```
yandex.ru, ya.ru, yandex.net, yastatic.net
vk.com, vk.me, vkontakte.ru
gosuslugi.ru, mos.ru
sberbank.ru, online.sberbank.ru
tinkoff.ru, tbank.ru
mail.ru, list.ru
ozon.ru, wildberries.ru
avito.ru, hh.ru
kinopoisk.ru
rutube.ru
```

---

## 9. Обслуживание и troubleshooting

### 9.1. Регулярные действия

| Действие | Частота | Как выполнить |
|----------|---------|---------------|
| Обновить Xray-core | 1 раз/мес | Панель -> Overview -> Xray -> Update |
| Обновить 3X-UI | По мере выхода | `x-ui update` |
| Обновить ОС | 1 раз/мес | `apt update && apt upgrade -y` |
| Обновить geosite/geoip | 1 раз/мес | wget-команды из раздела 8.5 |
| Проверить SSL | Автоматически | Let's Encrypt auto-renew |
| Проверить логи | При проблемах | `x-ui log` |

> **Критически важно:** используйте Xray-core **>= 25.12.8**. Старые версии детектируются через TLS 1.3 NewSessionTicket.

### 9.2. Если VPN перестал работать

Пошаговый алгоритм:

```
1. Проверить сервер (работает ли Xray?)
   ssh -p 49152 root@<IP>
   x-ui status
                    |
                    v
2. Если Xray упал -- перезапустить
   x-ui restart
                    |
                    v
3. Проверить логи на ошибки
   x-ui log
                    |
                    v
4. Если основной порт (443) не работает:
   -> Переключиться на backup (8443 или 2053) в клиенте
                    |
                    v
5. Если ни один порт не работает (IP заблокирован):
   -> На Wi-Fi: Cloudflare CDN (Layer 1)
   -> На мобильном: Yandex Cloud Relay (Layer 2)
                    |
                    v
6. Если CDN и Relay не работают:
   -> WebRTC через Яндекс.Телемост (Layer 3, только десктоп)
                    |
                    v
7. Крайний случай:
   -> Пересоздать VPS с новым IP (см. 9.3)
```

**Типичные проблемы:**

| Проблема | Причина | Решение |
|----------|---------|---------|
| "Connection timeout" | IP или порт заблокирован | Попробовать другой порт/CDN |
| Работает по Wi-Fi, не работает на LTE | Мобильный DPI агрессивнее | Включить TLS-фрагментацию 100-400 |
| Низкая скорость | Нет BBR или плохой SNI | Проверить BBR, сменить SNI |
| Hiddify "failed to start background core" | Баг режима VPN | Переключить на "Системный прокси" |
| Время на устройстве неточное | Reality требует точное время | Включить автоматическое время |

**Альтернативные SNI** (если текущий блокируется):
- `www.microsoft.com` (основной)
- `dl.google.com`
- `www.apple.com`
- `gateway.icloud.com`
- `swdist.apple.com`

> Каждый альтернативный SNI требует отдельного inbound на сервере с тем же SNI в Target и SNI полях.

### 9.3. Если VPS заблокирован (Disaster Recovery)

Время восстановления: **~30 минут**.

1. Удалите старый сервер в панели провайдера
2. Создайте новый (тот же тариф, та же локация)
3. Скопируйте и запустите скрипт восстановления:

```bash
scp -P 22 quick-rebuild.sh root@<НОВЫЙ_IP>:/root/
ssh root@<НОВЫЙ_IP> "bash /root/quick-rebuild.sh"
```

Скрипт автоматически:
- Установит 3X-UI + Xray-core
- Создаст все inbound-ы (443, 8443, 2053, 2082)
- Применит BBR, DNS, UFW, fail2ban
- Настроит Nginx-камуфляж
- Установит мониторинг
- Выведет все credentials и VLESS-ссылки

4. Обновите DNS в Cloudflare (A-запись -> новый IP)
5. Обновите subscription/ссылки в клиентах

> Если у вас нет скрипта `quick-rebuild.sh` -- пройдите все шаги раздела 4 вручную. Это займёт ~1-2 часа вместо 30 минут.

### 9.4. Обновление компонентов

**Xray-core:**
- Через панель: 3X-UI -> Overview -> Xray Version -> Update
- Или SSH: проверьте официальные релизы на [github.com/XTLS/Xray-core](https://github.com/XTLS/Xray-core)

**3X-UI:**
```bash
x-ui update
```

**Geosite/GeoIP базы (для split routing):**
```bash
wget -O /usr/local/x-ui/bin/geosite.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget -O /usr/local/x-ui/bin/geoip.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
x-ui restart
```

---

## 10. Безопасность

### Основные правила

1. **Никогда не храните пароли в коде или конфигах в git.** Используйте `.env` файл и добавьте его в `.gitignore`.

2. **SSH-ключи вместо паролей.** На локальной машине:
   ```bash
   ssh-keygen -t ed25519 -C "your@email.com"
   ssh-copy-id -p 49152 root@<VPS_IP>
   ```
   После этого отключите вход по паролю в `/etc/ssh/sshd_config`:
   ```
   PasswordAuthentication no
   ```

3. **Нестандартный SSH-порт.** Порт 22 блокируется ТСПУ для некоторых зарубежных IP и сканируется ботами.

4. **fail2ban** -- автоматически банит IP после нескольких неудачных попыток входа.

5. **Файрвол (UFW)** -- открыты только нужные порты, всё остальное закрыто.

6. **Панель 3X-UI только через SSH-туннель** (для параноиков):
   ```bash
   ssh -p 49152 -L 54321:127.0.0.1:54321 root@<VPS_IP>
   ```
   Теперь панель доступна на `https://127.0.0.1:54321/...` -- трафик шифруется SSH.

7. **Nginx-камуфляж** -- если кто-то зайдёт на IP вашего сервера браузером, увидит обычную веб-страницу, а не подозрительную заглушку:
   ```bash
   apt install nginx -y
   # Настроить виртуальный хост с любым контентом
   ```

8. **Создайте отдельного пользователя** (не работайте от root постоянно):
   ```bash
   adduser vpnuser
   usermod -aG sudo vpnuser
   ```

9. **Регулярно обновляйте** Xray-core, 3X-UI и систему. Уязвимости в старых версиях могут быть использованы для детекции.

---

## 11. FAQ

### Можно ли использовать WireGuard?

**Нет.** WireGuard полностью детектируется и блокируется ТСПУ по UDP-структуре. В России он не работает с 2024 года. Используйте VLESS Reality.

Исключение: [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) -- обфусцированная версия WireGuard. Работает, но менее проверена чем VLESS Reality.

### Какой SNI лучше?

Рекомендуемые SNI (сайты с TLS 1.3 и H2, IP которых не заблокированы):
- `www.microsoft.com` -- наш основной выбор
- `dl.google.com` -- резервный
- `www.apple.com` -- резервный
- `gateway.icloud.com`

**Совет:** выбирайте сайт, IP которого географически близок к вашему VPS.

### Будет ли работать на мобильном интернете?

**Да**, но мобильные операторы (МТС, Мегафон, Yota, Tele2, Beeline) блокируют агрессивнее Wi-Fi. Включите TLS-фрагментацию (100-400 байт) в клиенте -- это критически важно для LTE.

### Сколько стоит?

- Минимум: ~2 EUR/мес (только VPS)
- С CDN: +1 EUR/год (домен)
- С Yandex Cloud relay: +~4-5 EUR/мес (preemptible VM)
- Итого максимум: ~8-9 EUR/мес

### Почему на сайте Yandex Cloud цены от 1700₽, а у вас 400-500₽?

На сайте показана обычная VM с полной мощностью CPU. Мы экономим двумя способами: **прерываемая VM** (в ~3 раза дешевле, перезапускается раз в сутки) и **20% мощности CPU** (relay не нужен полный процессор). Подробная разбивка — в [секции 6.2](#62-что-понадобится).

### Легально ли это?

VPN в России **не запрещён**. Запрещён обход блокировок (ст. 15.8 ФЗ-149), но:
- Статья направлена на VPN-**сервисы** (компании), а не на частных пользователей
- К физическим лицам эта статья **не применяется**
- За использование VPN в личных целях **никого не привлекали**

Тем не менее, используйте VPN ответственно и для законных целей.

### Что если провайдер включил белые списки?

Это основной сценарий для мобильных операторов в 2026 году:
- **Layer 1 (Cloudflare):** ⚠ **не работает** при белых списках (CF блокируется с 2025)
- **Layer 2 (Yandex Cloud relay):** ✅ **основной метод** -- IP Yandex Cloud в белых списках
- **Layer 3 (WebRTC):** Яндекс.Телемост всегда в белом списке (но только десктоп)

Для обхода белых списков на мобильной сети используйте **Layer 2** (раздел 6).

### Можно ли расшарить VPN с семьёй/друзьями?

Да. В 3X-UI можно создать отдельных клиентов (каждый со своим UUID) в одном inbound. Каждый получит свою VLESS-ссылку. VPS с 4 GB RAM и безлимитным трафиком спокойно выдержит 5-10 одновременных пользователей.

### Как проверить что VPN работает правильно?

1. **2ip.ru** -- должен показать IP вашего VPS (Швеция)
2. **YouTube** -- должен открываться без ограничений
3. **Яндекс** -- должен работать **без VPN** (через split routing) с российским IP
4. **Госуслуги/банки** -- должны работать напрямую (split routing)

### Время на устройстве важно?

**Да!** Reality использует timestamp для handshake. Расхождение больше ~30 секунд = соединение не установится. Убедитесь что на всех устройствах включена автоматическая синхронизация времени.

---

## 12. Полезные ссылки

### Проекты

| Проект | Ссылка |
|--------|--------|
| **Xray-core** (ядро VLESS Reality) | [github.com/XTLS/Xray-core](https://github.com/XTLS/Xray-core) |
| **3X-UI** (панель управления) | [github.com/mhsanaei/3x-ui](https://github.com/mhsanaei/3x-ui) |
| **OlcRTC** (WebRTC через Телемост) | [github.com/zarazaex69/olcRTC](https://github.com/zarazaex69/olcRTC) |
| **GoodbyeDPI** (локальный обход DPI) | [github.com/ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) |
| **zapret** (локальный обход DPI) | [github.com/bol-van/zapret](https://github.com/bol-van/zapret) |

### Клиенты

| Клиент | Платформа | Ссылка |
|--------|-----------|--------|
| **Hiddify** | Windows, macOS, Linux, Android | [hiddify.com](https://hiddify.com/) |
| **Shadowrocket** | iOS | App Store ($2.99) |
| **v2RayTun** | iOS | App Store (бесплатно) |
| **v2rayNG** | Android | [GitHub](https://github.com/2dust/v2rayNG) / Google Play |
| **nekoray** | Windows, Linux | [GitHub](https://github.com/MatsuriDayo/nekoray) |

### Статьи на Habr

| Тема | Ссылка |
|------|--------|
| История блокировок в РФ (2026) | [habr.com/ru/articles/1014038/](https://habr.com/ru/articles/1014038/) |
| OlcRTC -- WebRTC через Яндекс.Телемост (2026) | [habr.com/ru/articles/1020114/](https://habr.com/ru/articles/1020114/) |
| Белые списки и обход DPI (2026) | [habr.com/ru/articles/1013122/](https://habr.com/ru/articles/1013122/) |
| Быстрая настройка VPS и VLESS | [habr.com/ru/articles/995542/](https://habr.com/ru/articles/995542/) |
| Обход белых списков и цепочки | [habr.com/en/articles/990206/](https://habr.com/en/articles/990206/) |
| Установка VPN с VLESS и Reality | [habr.com/en/articles/990128/](https://habr.com/en/articles/990128/) |
| VLESS+Reality и Multi-hop | [habr.com/ru/articles/926786/](https://habr.com/ru/articles/926786/) |

### Дополнительные инструменты

| Инструмент | Назначение |
|------------|-----------|
| [UptimeRobot](https://uptimerobot.com/) | Бесплатный мониторинг доступности сервера |
| [Cloudflare](https://cloudflare.com/) | CDN и DNS (бесплатный план) |
| [Yandex Cloud](https://cloud.yandex.ru/) | Облако для relay (IP в белых списках) |
| [Namecheap](https://namecheap.com/) | Дешёвые домены |
| [AlphaVPS](https://alphavps.com/) | KVM VPS в EU (рекомендуемый) |
| [RackNerd](https://racknerd.com/) | Бюджетные VPS от ~$1/мес |

---

## Заключение

Вы построили 4-уровневую VPN-систему, которая устойчива к большинству методов блокировки:

- **Layer 0** (VLESS Reality) -- основной, работает в 95% случаев
- **Layer 1** (Cloudflare CDN) -- если IP VPS заблокирован (домашний Wi-Fi)
- **Layer 2** (Yandex Cloud relay) -- **при белых списках на мобильной сети**
- **Layer 3** (WebRTC) -- аварийный, последний рубеж

> **Ключевое обновление 2026:** Cloudflare блокируется ТСПУ. Для мобильной сети Layer 2 (Yandex Cloud) стал основным резервным методом.

Общая стоимость: **~2 EUR/мес** (базовый), **~6 EUR/мес** (с relay). Время настройки с нуля: **2-4 часа** (Layer 0 + 1). Время деплоя Layer 2: **~10 минут** (скрипт `deploy-relay-yc.sh`). Время восстановления при блокировке IP: **~30 минут** с подготовленными скриптами.

Главное правило: **всегда имейте запасной план**. Если текущий метод перестал работать -- переключайтесь на следующий уровень. Именно многоуровневая архитектура делает эту систему надёжной.

---

*Это руководство создано на основе личного опыта эксплуатации VPN-инфраструктуры. Проект open-source, для личного использования. Все технические детали актуальны на апрель 2026 года.*
