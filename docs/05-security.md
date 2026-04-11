# 5. Безопасность и оптимизация

## Hardening сервера

### Сменить пароли
```bash
# SSH пароль
passwd

# Панель 3X-UI
x-ui setting -username <NEW_USER> -password <NEW_PASSWORD>
x-ui restart
```

### Создать отдельного пользователя
```bash
adduser vpnuser
usermod -aG sudo vpnuser
```

### Изменить SSH-порт
```bash
nano /etc/ssh/sshd_config
# Изменить: Port 22 -> Port СЛУЧАЙНЫЙ (10001-65535)
# Изменить: PermitRootLogin yes -> no
systemctl restart sshd
```

### Настроить firewall
```bash
apt install ufw -y
ufw allow <SSH_PORT>
ufw allow 80        # для Let's Encrypt
ufw allow 443       # для VLESS Reality
ufw allow <PANEL_PORT>  # для панели 3X-UI
ufw enable
```

### Установить fail2ban
```bash
apt install fail2ban -y
systemctl enable fail2ban
```

### Nginx-камуфляж
Установить Nginx с реальным сайтом — если кто-то зайдёт на IP браузером, увидит обычную веб-страницу:
```bash
apt install nginx -y
# Настроить виртуальный хост с контентом
```

---

## Утечки трафика в режиме системного прокси

### Проблема

При использовании VPN-клиента в режиме **"Системный прокси"** (вместо TUN/VPN) перехватывается **только TCP-трафик**. Весь UDP-трафик идёт напрямую через провайдера, вызывая три типа утечек:

| Утечка | Протокол | Что происходит |
|--------|----------|----------------|
| **QUIC/HTTP3** | UDP:443 | Google, Cloudflare (Claude.ai), YouTube используют QUIC. Браузер пробует QUIC первым → трафик идёт мимо VPN → сервис видит реальный IP |
| **DNS** | UDP:53 | DNS-запросы идут через ISP → резолвер выдаёт российскую геолокацию |
| **WebRTC** | UDP/STUN | Браузер утекает реальный IP через WebRTC ICE candidates |

**Результат:** 2ip.ru показывает VPN IP (тестирует через HTTP/TCP), но Google, Claude.ai и другие сервисы видят реальный российский IP (через QUIC/UDP).

### Решение

**TUN-режим обязателен.** TUN создаёт виртуальный сетевой адаптер, который перехватывает **весь** трафик (TCP + UDP + DNS + QUIC). Ни один пакет не утекает.

В v2rayN: Settings → TUN Mode → включить.
В Hiddify: Настройки → Входящие → Режим службы → "VPN" (не "Системный прокси").

> Коммерческие VPN работают именно в TUN-режиме — поэтому у них нет этой проблемы.

### Выбор ядра в v2rayN: sing-box вместо Xray

v2rayN поддерживает два ядра: **Xray** и **sing-box**. Для TUN-режима рекомендуется **sing-box core**:

| | Xray core | sing-box core |
|---|-----------|---------------|
| TUN | Через sing-box (отдельный процесс) | Нативный (один процесс) |
| UDP/QUIC | Передаётся через SOCKS5 handoff → нестабильно | Нативная обработка → стабильно |
| flow xtls-rprx-vision | Поддерживается | Не передаёт корректно |
| **Рекомендация** | Не использовать с TUN | **Использовать** |

**Настройка:** v2rayN → Settings → Core Type settings → выбрать **sing_box** → Confirm.

> При использовании sing-box core `flow` на сервере должен быть **пустым** (без xtls-rprx-vision), иначе сервер отклонит подключение с ошибкой "client flow is empty".

### Экстренный фикс (если TUN не работает)

Если невозможно использовать TUN, минимизировать утечки:

1. **Отключить QUIC в браузере:**
   - Chrome: `chrome://flags/#enable-quic` → Disabled
   - Edge: `edge://flags/#enable-quic` → Disabled
   - Firefox: `about:config` → `network.http.http3.enable` → false

2. **DNS-over-HTTPS в Windows:**
   - Settings → Network → DNS → Manual
   - Preferred: `1.1.1.1`, DNS over HTTPS: On
   - Alternate: `8.8.8.8`, DNS over HTTPS: On

3. **Заблокировать WebRTC:**
   - Chrome/Edge: расширение "WebRTC Leak Prevent"
   - Firefox: `about:config` → `media.peerconnection.enabled` → false

### Чек-лист проверки утечек

После подключения к VPN проверить:

| Тест | URL | Ожидаемый результат |
|------|-----|---------------------|
| IP-адрес | https://browserleaks.com/ip | Шведский IP |
| DNS leak | https://browserleaks.com/dns | DNS-серверы НЕ российские |
| WebRTC leak | https://browserleaks.com/webrtc | Не показывает реальный IP |
| Cloudflare geo | https://www.cloudflare.com/cdn-cgi/trace | `loc=SE` (не `RU`) |
| Основной тест | https://2ip.ru | Шведский IP |

Если хотя бы один тест показывает российский IP/DNS — есть утечка. Включите TUN-режим.

---

## Оптимизация стабильности (для мобильных сетей)

### Проблема
На мобильном LTE (МТС, Мегафон, Yota, Tele2, Beeline) VPN может работать нестабильно:
- Частые отключения
- Зависание на "Подключение..."
- Потеря соединения при переключении Wi-Fi <-> LTE

**Причины:** мобильные операторы используют более агрессивный DPI, а стандартные настройки TCP не оптимальны для lossy мобильных соединений.

### Клиентская оптимизация

#### Версия клиента
- Использовать только **стабильные** релизы Hiddify (не dev/pre-release)
- На Android рекомендуется **v2rayNG** (стабильнее на мобильных сетях)

#### TLS-фрагментация (критично для LTE)
Разбивает TLS ClientHello на мелкие куски, обходя DPI-сигнатуры:

В Hiddify: **Настройки -> Config Options -> Fragment:**
| Параметр | Значение |
|----------|----------|
| Enable | Включить |
| Mode | `tlshello` |
| Size | `100-400` |
| Interval | `1-3` ms |

> Размер 1-5 байт (старая рекомендация) слишком агрессивен: при 300-байт ClientHello нужно 60-300 фрагментов -> 300-600 мс overhead на каждое соединение -> видео не открывается.

В v2RayTun (iOS): **Fragment settings -> Length: `100-400`**

#### DNS в клиенте
| Параметр | Значение | Пояснение |
|----------|----------|-----------|
| Remote DNS | `https://1.1.1.1/dns-query` | DoH через туннель |
| Direct DNS | `https://77.88.8.8/dns-query` | Yandex DoH, работает в РФ без VPN |
| IPv6 | Отключить | Предотвращает утечки |

#### Альтернативные SNI
Если текущий SNI (`www.microsoft.com`) блокируется оператором, попробовать:
- `dl.google.com`
- `www.apple.com`
- `gateway.icloud.com`
- `swdist.apple.com`

> Требует создания соответствующего inbound на сервере с таким же SNI/Target.

### Серверная оптимизация

#### BBR + TCP-тюнинг
BBR congestion control критически важен для мобильных соединений. Добавить в `/etc/sysctl.conf`:
```ini
# BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Буферы
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Оптимизации
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 4096
net.ipv4.tcp_slow_start_after_idle = 0
```
Применить: `sysctl -p`

#### DNS на сервере
```bash
apt install systemd-resolved -y
```
В `/etc/systemd/resolved.conf`:
```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 8.8.4.4
DNSOverTLS=yes
```

В Xray DNS (3X-UI -> Xray Settings):
```json
{"dns":{"servers":["https+local://1.1.1.1/dns-query"],"queryStrategy":"UseIPv4"}}
```

#### Nginx-камуфляж (защита от active probing)
Если ТСПУ подключается к серверу напрямую (не как VLESS-клиент), он должен видеть обычный сайт:
```bash
apt install nginx -y
```
Настроить на `127.0.0.1:8081`, в 3X-UI добавить fallback `127.0.0.1:8081`.

#### Backup inbound-ы
Создать дополнительные inbound-ы на разных портах для тестирования:
- Port 8443, SNI `dl.google.com`, TCP RAW, Reality
- Port 2053, SNI `www.apple.com`, TCP RAW, Reality

### Автоматизация
Все серверные оптимизации можно применить одним скриптом:
```bash
# Скопировать optimize-server.sh на сервер и запустить
python ssh_exec.py deploy optimize-server.sh
```
