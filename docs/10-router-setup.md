# 10. VPN на роутере

## Зачем VPN на роутере

Настройка VPN на уровне роутера вместо приложений на каждом устройстве:

- **Все устройства защищены** — Smart TV, игровые консоли, IoT, гостевые устройства
- **Не нужен клиент** — не надо ставить v2rayN/Hiddify на каждое устройство
- **Split routing для всех** — российские сайты напрямую, остальное через VPN
- **Одна точка управления** — обновил конфиг на роутере, все устройства работают

**Ограничения:**
- Один VPN-профиль на всю сеть (нельзя разные серверы для разных устройств)
- Скорость зависит от CPU роутера (шифрование нагружает процессор)
- Сложнее первоначальная настройка по сравнению с приложением

---

## Матрица совместимости

| Платформа | VLESS Reality | Сложность | Рекомендация |
|-----------|--------------|-----------|--------------|
| **Keenetic** (XKeen) | Отлично | Средняя | Лучший выбор для РФ |
| **OpenWrt** (PassWall2) | Отлично | Высокая | Универсальное решение |
| **ASUS Merlin** (XrayUI) | Хорошо | Средняя | Для владельцев ASUS |
| MikroTik (контейнер) | Плохо | Очень высокая | Не рекомендуется |
| TP-Link (stock) | Нет поддержки | — | Перепрошить на OpenWrt |
| Xiaomi (stock) | Нет поддержки | — | Перепрошить на OpenWrt |

> **Почему нет WireGuard/OpenVPN?** ТСПУ в РФ уверенно детектирует и блокирует стандартные VPN-протоколы (WireGuard, OpenVPN, IPSec). VLESS Reality маскирует трафик под обычный HTTPS к microsoft.com — DPI не может отличить его от легитимного трафика.

---

## Подключение к нашему серверу

Все варианты ниже подключаются к одной и той же серверной инфраструктуре. Параметры подключения (взять из панели 3X-UI):

| Параметр | Значение | Где взять |
|----------|----------|-----------|
| Протокол | VLESS | — |
| Адрес сервера | `YOUR_SERVER_IP` | `.env` → `VPS_IP` |
| Порт | 443 (основной), 8443, 2053 (резервные) | — |
| UUID | `YOUR_UUID` | 3X-UI → Inbounds → reality-main |
| Encryption | none | — |
| Flow | (пусто) | — |
| Transport | TCP | — |
| Security | Reality | — |
| SNI | www.microsoft.com (443), dl.google.com (8443), www.apple.com (2053) | — |
| Fingerprint | chrome | — |
| Public Key | `YOUR_PUBLIC_KEY` | 3X-UI → Inbounds → reality-main |
| Short ID | `YOUR_SHORT_ID` | 3X-UI → Inbounds → reality-main |

---

## Вариант A: Keenetic + XKeen (рекомендуемый)

Самый популярный роутер в РФ. Утилита **XKeen** от сообщества даёт полную поддержку Xray/VLESS Reality с веб-интерфейсом.

### Требования

- Keenetic с KeeneticOS 4.x или 5.x (Hopper KN-3810, Giga, Ultra, Viva, Hero 4G, Giant)
- USB-флешка минимум 1 ГБ, отформатированная в EXT4
- SSH-доступ к роутеру

### Шаг 1: Установка Entware

1. Отформатировать USB-флешку в EXT4 (из Linux/macOS или через утилиту на Windows)
2. Вставить флешку в USB-порт роутера
3. В веб-интерфейсе Keenetic: **Управление → Общие настройки → Обновления и компоненты**
4. Установить компонент **"Пакеты OPKG"** (он же Entware)
5. Перезагрузить роутер

### Шаг 2: Установка XKeen

Подключиться по SSH к роутеру (порт 222 или 22, в зависимости от модели):

```bash
ssh admin@192.168.1.1 -p 222
```

Установить XKeen:

```bash
opkg update
opkg install curl
curl -sSL https://raw.githubusercontent.com/Skrill0/XKeen/master/install.sh | sh
```

> **Альтернативный репозиторий** (форк с активной поддержкой): `https://github.com/Corvus-Malus/XKeen`

После установки XKeen автоматически скачает Xray-core и настроит службу.

### Шаг 3: Настройка VLESS Reality

Запустить мастер настройки XKeen:

```bash
xkeen
```

Выбрать **"Настройка подключения"** и ввести параметры:

- **Протокол:** VLESS
- **Адрес:** `YOUR_SERVER_IP`
- **Порт:** `443`
- **UUID:** `YOUR_UUID`
- **Security:** Reality
- **SNI:** `www.microsoft.com`
- **Fingerprint:** `chrome`
- **Public Key:** `YOUR_PUBLIC_KEY`
- **Short ID:** `YOUR_SHORT_ID`

Или вставить VLESS URI из 3X-UI:
```
vless://YOUR_UUID@YOUR_SERVER_IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=YOUR_PUBLIC_KEY&sid=YOUR_SHORT_ID&type=tcp#Router-Reality
```

### Шаг 4: Настройка split routing

В меню XKeen выбрать **режим работы**:

| Режим | Описание |
|-------|----------|
| **Direct** | Весь трафик напрямую (VPN выключен) |
| **Split** (рекомендуемый) | Заблокированные сайты через VPN, российские напрямую |
| **Full** | Весь трафик через VPN |

Выбрать **Split** и настроить источники GeoIP/GeoSite:

```bash
# В меню XKeen → Маршрутизация → Источники списков:
# - AntiZapret (рекомендуемый — содержит актуальный реестр блокировок)
# - Antifilter (альтернатива)
# - v2fly community lists (geosite:category-ru)
```

XKeen автоматически обновляет списки по cron.

### Шаг 5: Проверка

1. С любого устройства в сети открыть https://2ip.ru — должен показать **российский IP** (трафик идёт напрямую)
2. Открыть https://ifconfig.me или https://whoer.net — должен показать **шведский IP** (трафик через VPN)
3. YouTube, Google, ChatGPT — должны работать без ограничений

### Шаг 6: Резервные серверы

Для failover добавить в XKeen ещё два профиля:

| Профиль | Порт | SNI |
|---------|------|-----|
| Основной | 443 | www.microsoft.com |
| Резерв 1 | 8443 | dl.google.com |
| Резерв 2 | 2053 | www.apple.com |

XKeen поддерживает автоматическое переключение (URL-test) между профилями.

---

## Вариант B: OpenWrt + PassWall2

Универсальное решение для любого роутера с поддержкой OpenWrt: Xiaomi, TP-Link, Netgear и др.

### Требования

- Роутер с OpenWrt 21.02+ (лучше 23.05+)
- Минимум 128 МБ RAM (рекомендуется 256 МБ)
- Минимум 30 МБ свободной Flash (для xray-core)
- Совместимые модели: Xiaomi AX3000T, AX3600, AX3200; TP-Link Archer AX series; и др.

> Таблица совместимости: https://openwrt.org/toh/start

### Шаг 1: Прошивка OpenWrt

Если роутер уже на OpenWrt — пропустить. Иначе:

1. Найти свою модель в таблице совместимости OpenWrt
2. Скачать образ прошивки для своего роутера
3. Прошить через веб-интерфейс роутера (обычно System → Firmware Upgrade)
4. Дождаться перезагрузки, подключиться к `192.168.1.1`

### Шаг 2: Установка Xray и PassWall2

Подключиться по SSH:

```bash
ssh root@192.168.1.1
```

Установить пакеты:

```bash
# Обновить списки пакетов
opkg update

# Установить Xray-core и геоданные
opkg install xray-core xray-geodata-geoip xray-geodata-geosite

# Добавить репозиторий PassWall2
# (URL зависит от архитектуры роутера — aarch64, mipsel, x86_64)
# Скачать .ipk с https://github.com/xiaorouji/openwrt-passwall2/releases

# Установить PassWall2 и зависимости
opkg install luci-app-passwall2
```

> **Альтернатива PassWall2:** `luci-app-v2raya` (v2rayA) — проще в настройке, веб-интерфейс на порту 2017.

### Шаг 3: Настройка VLESS Reality в PassWall2

1. Открыть веб-интерфейс: `http://192.168.1.1` → **Services → PassWall2**
2. Перейти на вкладку **Node List → Add**
3. Заполнить параметры:

| Поле | Значение |
|------|----------|
| Type | Xray → VLESS |
| Address | `YOUR_SERVER_IP` |
| Port | `443` |
| UUID | `YOUR_UUID` |
| Encryption | none |
| Flow | (пусто) |
| Transport | TCP |
| TLS | Reality |
| SNI | `www.microsoft.com` |
| Fingerprint | chrome |
| Public Key | `YOUR_PUBLIC_KEY` |
| Short ID | `YOUR_SHORT_ID` |

4. Нажать **Save & Apply**

### Шаг 4: Настройка split routing

В PassWall2 → **Basic Settings**:

- **TCP Default Proxy Mode:** `GFW List` или `Proxy all except China` (адаптировано для РФ)
- **UDP Default Proxy Mode:** то же

Для кастомных правил (российские домены напрямую):

1. PassWall2 → **Rule Manage → Direct List**
2. Добавить домены:
```
geosite:category-ru
domain:yandex.ru
domain:vk.com
domain:sberbank.ru
domain:gosuslugi.ru
domain:mail.ru
```

3. PassWall2 → **Rule Manage → Direct IP**
```
geoip:ru
```

Или загрузить готовый Xray JSON конфиг: [`client-configs/router-xray-config.json`](../client-configs/router-xray-config.json)

### Шаг 5: Проверка

1. Перезагрузить роутер или перезапустить PassWall2
2. Проверить статус: PassWall2 → Overview → должен быть зелёный индикатор
3. С устройства в сети: `https://2ip.ru` → РФ, `https://ifconfig.me` → SE

### Альтернатива: HomeProxy (sing-box)

Если нужен более лёгкий вариант (меньше нагрузка на CPU):

```bash
opkg install luci-app-homeproxy
```

> **Важно:** sing-box НЕ поддерживает Reality. HomeProxy подходит только для VLESS без Reality (через Cloudflare CDN / WebSocket).

---

## Вариант C: ASUS Merlin + XrayUI

Для роутеров ASUS с кастомной прошивкой Asuswrt-Merlin.

### Требования

- ASUS RT-AX86U, RT-AX88U, GT-AX11000, RT-AX86U Pro, RT-AX68U или другой совместимый
- Asuswrt-Merlin 384.15+ или 3006.102.1+
- USB-накопитель для Entware

### Шаг 1: Установка Merlin и Entware

1. Скачать прошивку Merlin для своего роутера: https://www.asuswrt-merlin.net/
2. Прошить: Administration → Firmware Upgrade → Upload
3. После перезагрузки подключить USB-накопитель
4. Administration → System → Enable JFFS custom scripts: **Yes**
5. Установить Entware через `amtm`:
```bash
ssh admin@192.168.1.1
amtm
# Выбрать "ep" → Install Entware
```

### Шаг 2: Установка XrayUI

```bash
ssh admin@192.168.1.1

# Установить через Entware
opkg update
opkg install curl jq

# Установить XrayUI
curl -sSL https://raw.githubusercontent.com/DanielLavrushin/asuswrt-merlin-xrayui/main/install.sh | sh
```

После установки XrayUI появится в меню роутера: **VPN → XrayUI**

### Шаг 3: Настройка VLESS Reality

1. Веб-интерфейс роутера → **VPN → XrayUI**
2. Добавить новый профиль (Add Server)
3. Вставить VLESS URI из 3X-UI:
```
vless://YOUR_UUID@YOUR_SERVER_IP:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=YOUR_PUBLIC_KEY&sid=YOUR_SHORT_ID&type=tcp#Router-Reality
```
4. Включить подключение
5. Настроить routing rules (аналогично PassWall2 — прямой доступ для geoip:ru)

### Шаг 4: Проверка

1. VPN → XrayUI → Status → должен показать Connected
2. С устройства: `https://2ip.ru` → РФ, `https://ifconfig.me` → SE

---

## Готовый Xray JSON конфиг

Файл [`client-configs/router-xray-config.json`](../client-configs/router-xray-config.json) содержит готовый конфиг для роутера:

- **3 outbound** — основной (443) + два резервных (8443, 2053)
- **Split DNS** — российские домены через Яндекс DNS (77.88.8.8), остальные через Cloudflare (1.1.1.1)
- **Split routing** — geosite:category-ru + geoip:ru → direct, остальное → proxy
- **Блокировка рекламы** — geosite:category-ads-all → block
- **3 inbound** — TProxy (12345), SOCKS5 (10808), HTTP (10809)

Перед использованием заменить placeholder-ы:
- `YOUR_SERVER_IP` → IP VPS из `.env`
- `YOUR_UUID` → UUID из 3X-UI
- `YOUR_PUBLIC_KEY` → публичный ключ Reality из 3X-UI
- `YOUR_SHORT_ID` → Short ID из 3X-UI

---

## Исключение устройств из VPN

Некоторые устройства (например, рабочий ноутбук с корпоративным VPN) нужно исключить:

**Keenetic (XKeen):**
В меню XKeen → Исключения → добавить IP или MAC-адрес устройства.

**OpenWrt (PassWall2):**
PassWall2 → Basic Settings → Proxy Mode → добавить IP в список исключений (No Proxy).

**ASUS Merlin (XrayUI):**
VPN → XrayUI → Routing → добавить IP-адрес устройства с правилом `direct`.

---

## Обновление GeoIP/GeoSite

Списки заблокированных доменов/IP обновляются. Настроить автоматическое обновление:

**Keenetic:** XKeen обновляет автоматически (настраивается в меню утилиты).

**OpenWrt:**
```bash
# Добавить в crontab (обновление раз в неделю)
crontab -e
# Добавить строку:
0 4 * * 1 /usr/bin/xray-geodata-update.sh
```

**ASUS Merlin:**
```bash
# Добавить в /jffs/scripts/services-start
cru a xray_geo_update "0 4 * * 1 /opt/sbin/xray-geodata-update.sh"
```

---

## Troubleshooting

| Проблема | Причина | Решение |
|----------|---------|---------|
| Медленная скорость через VPN | Слабый CPU роутера не тянет шифрование | Проверить загрузку CPU (`top`). Если >80% — роутер слишком слабый. Использовать клиент на устройстве |
| DNS leak (2ip.ru показывает провайдера) | DNS-запросы идут мимо VPN | Настроить DNS в Xray конфиге (split DNS). Отключить DNS провайдера в WAN |
| Российские сайты не открываются | Split routing не работает | Проверить правила geosite:category-ru и geoip:ru в routing. Обновить geodata |
| VPN работает, но скорость <10 Мбит | BBR не включён на сервере | `python ssh_exec.py exec "sysctl net.ipv4.tcp_congestion_control"` — должен быть `bbr` |
| Нет подключения к серверу | Порт 443 заблокирован провайдером | Переключиться на порт 8443 или 2053 (резервные SNI) |
| XKeen не устанавливается | Старая версия KeeneticOS | Обновить прошивку до KeeneticOS 4.x+ |
| PassWall2 не видит xray-core | Не установлен пакет | `opkg install xray-core` и перезапустить PassWall2 |

---

## FAQ

**Можно ли использовать VPN на роутере и клиент на устройстве одновременно?**
Технически да, но не рекомендуется — будет двойное шифрование, лишняя нагрузка и пониженная скорость. Если VPN на роутере — клиент на устройстве лучше выключить.

**Какой минимальный роутер потянет VLESS Reality?**
Keenetic Viva (KN-1912) или Xiaomi AX3000T — минимально комфортные модели. Dual-core CPU, 256 МБ RAM. На слабых однопроцессорных роутерах (TP-Link Archer C7 и ниже) скорость будет ограничена до 20-50 Мбит/с.

**Как обновить конфиг при смене сервера?**
Заменить `YOUR_SERVER_IP`, `YOUR_UUID`, ключи в конфиге и перезапустить Xray на роутере. Или обновить subscription URL в XKeen/PassWall2.

**Гости Wi-Fi тоже пойдут через VPN?**
Да. Если нужно исключить — создать отдельную гостевую сеть на роутере без маршрутизации через Xray (настраивается в firewall rules).

**Как быстро проверить работает ли VPN на роутере?**
```bash
# С компьютера в сети:
curl https://ifconfig.me    # Должен показать шведский IP
curl https://2ip.ru         # Должен показать российский IP (split routing)
```
