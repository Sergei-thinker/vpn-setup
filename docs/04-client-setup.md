# 4. Настройка клиентов

## Windows — v2rayN (рекомендуемый)

v2rayN — лучший Windows-клиент для VLESS Reality: тот же Xray-core что на сервере, встроенный пресет маршрутизации для России, стабильный TUN-режим.

1. Скачать последнюю версию с [GitHub](https://github.com/2dust/v2rayN/releases) (файл `v2rayN-windows-64.zip`)
2. Распаковать в удобную папку (например, `C:\v2rayN`)
3. **Запустить от имени администратора** (правый клик → Run as Administrator)
4. Скопировать subscription-ссылку из панели 3X-UI
5. **Подписки → Добавить подписку → Вставить URL → OK**
6. **Обновить подписку** (Ctrl+U) — появится профиль VLESS Reality
7. Включить **TUN-режим**:
   - Settings → TUN Mode → включить
   - Stack: `Mixed` (рекомендуется) или `gVisor`
8. Включить пресет **Россия** для split routing:
   - Settings → Regional Presets → Russia
   - Settings → **Routing Settings** → выбрать набор **"RUv1-Всё, кроме РФ"** (НЕ "RUv1-Всё"!)
   - "RUv1-Всё" гонит весь трафик через VPN — российские сервисы (Rutube, Кинопоиск, банки) будут блокировать по иностранному IP
9. Выбрать сервер → нажать кнопку подключения
10. Проверить: https://2ip.ru → Россия (RU), https://ifconfig.me → Швеция (SE)

Подробная инструкция: [client-configs/v2rayn-setup.md](../client-configs/v2rayn-setup.md)

> **⚠️ TUN-режим обязателен!** Без TUN (в режиме системного прокси) QUIC/UDP трафик идёт напрямую через провайдера — Google, Claude.ai и другие сервисы увидят ваш реальный IP. Подробнее: [05-security.md → Утечки трафика](05-security.md#утечки-трафика-в-режиме-системного-прокси).

## Windows — Hiddify (альтернатива)

> **⚠️ Только TUN-режим!** Режим "Системный прокси" перехватывает только TCP, QUIC/UDP утекает. Если TUN не работает — используйте v2rayN.

1. Скачать с [hiddify.com](https://hiddify.com/)
2. **Запустить от имени администратора**
3. Скопировать subscription-ссылку из панели 3X-UI
4. В Hiddify нажать "+" -> "Буфер обмена"
5. **Настройки → Входящие → Режим службы → "VPN"** (НЕ "Системный прокси"!)
6. Нажать кнопку подключения на главном экране
7. Проверить IP на 2ip.ru

> Если TUN-режим даёт ошибку "failed to start background core": запустить от админа, обновить Hiddify до последней версии, переустановить TUN-драйвер. Если не помогает — используйте v2rayN.

## Android — v2rayNG
1. Установить из Google Play или [GitHub](https://github.com/2dust/v2rayNG)
2. Нажать "+" -> "Scan QR code"
3. Отсканировать QR-код из панели 3X-UI (reality-xxx)
4. Нажать кнопку подключения
5. Проверить IP на 2ip.ru

## Android — Hiddify
1. Установить из Google Play
2. Добавить subscription через буфер обмена
3. Подключиться

## iOS — v2RayTun (текущий клиент)
1. Установить из App Store
2. Импортировать конфиг через QR или ссылку из 3X-UI
3. **Критически важно для скорости**: настройка фрагментации:
   - Fragment: включить
   - Packets: `tlshello`
   - **Length: `100-400`** (НЕ 1-5 — это убивает скорость!)
   - Interval: `1-3` ms
4. UDP Relay: включить (для QUIC/видео)

> **Почему 100-400, а не 1-5?** TLS ClientHello ~ 300 байт. При 1-5 байт/фрагмент нужно 60-300 фрагментов на каждое соединение -> +300-600 мс overhead. Видео требует 20-50+ параллельных соединений -> таймаут. При 100-400 байт — 1-3 фрагмента -> 10-30 мс.

## iOS — Shadowrocket (рекомендуется, лучшая скорость)
Shadowrocket ($2.99 в App Store) — самый производительный iOS-клиент для VLESS:
1. Установить из App Store (требует аккаунт в нероссийском App Store)
2. Скопировать VLESS-ссылку из 3X-UI -> нажать "+"
3. В настройках подключения включить:
   - **UDP Relay**: On (критично для YouTube/видео — QUIC/HTTP3)
   - **Sniffing**: On
4. Проверить IP: 2ip.ru должен показать Швецию

> Shadowrocket даёт +20-40% скорости по сравнению с v2RayTun на видеостриминге.

## iOS — Streisand / FoXray / V2Box
1. Установить из App Store
2. Импортировать конфиг через QR или ссылку

## macOS / Linux — v2rayN или Hiddify
1. **v2rayN** (рекомендуемый): скачать с [GitHub](https://github.com/2dust/v2rayN/releases), поддерживает macOS и Linux
2. **Hiddify**: скачать с [hiddify.com](https://hiddify.com/)
3. Импортировать subscription
4. **Включить TUN-режим** (обязательно!)
5. Подключиться

> ~~Nekoray/NekoBox~~ — проект **архивирован** (март 2025), не рекомендуется. Нет обновлений безопасности.

---

## Layer 2: Relay через российский VPS

Дополнительный сервер-relay для ситуаций когда шведский IP заблокирован.
Подробные инструкции: [client-configs/relay-config.md](../client-configs/relay-config.md)

Краткая настройка:
1. Получить VLESS URI relay из `/root/relay-credentials.txt` на relay VPS
2. Импортировать в клиент как обычный VLESS-сервер
3. Рекомендуется настроить URL-test группу для auto-failover

---

## Layer 3: WebRTC OlcRTC (аварийный канал)

> **Только Windows (через WSL2) и Linux.** iOS и Android НЕ поддерживаются.

OlcRTC туннелирует трафик через WebRTC DataChannel в Яндекс.Телемост.
Используется ТОЛЬКО когда все остальные слои (0, 1, 2) заблокированы.

### Windows (WSL2)
1. Убедитесь что WSL2 установлен: `wsl --status`
2. Запустите `olcrtc-client.bat` из корня проекта
3. Введите Conference ID и Encryption Key из Телемост
4. SOCKS5h прокси будет доступен на `localhost:8809`
5. В Hiddify: добавить SOCKS5 прокси → `127.0.0.1:8809`

### Linux
1. Запустите `bash olcrtc-wsl-client.sh`
2. SOCKS5h на `localhost:8809`
3. Проверка: `curl --socks5h localhost:8809 https://ifconfig.me`

### iOS / Android — НЕ ПОДДЕРЖИВАЕТСЯ
Layer 3 через WebRTC невозможен на мобильных устройствах:
- Нет клиента OlcRTC для iOS/Android
- iOS не поддерживает произвольный WebRTC DataChannel tunneling
- **Для мобильных устройств Layer 2 (relay) — последний рубеж защиты**
