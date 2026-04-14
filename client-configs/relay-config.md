# Layer 1: Russian Relay VPS — Конфигурация клиентов

## Обзор

Relay — резервный канал для случаев, когда шведский VPS IP полностью заблокирован ТСПУ.
Трафик идёт: **Клиент → Российский VPS → Шведский VPS → Интернет**.

### Два варианта relay

| Вариант | SNI | Порт | Скрипт | Когда использовать |
|---------|-----|------|--------|--------------------|
| **Yandex Cloud** (рекомендуемый) | `yandex.ru` | 15443 | `deploy-relay-yc.sh` | Белые списки на мобильной сети |
| Generic VPS (Timeweb и т.д.) | `gosuslugi.ru` | 443 | `deploy-relay.sh` | Если YC заблокировали |

## VLESS URI

### Yandex Cloud relay

После запуска `deploy-relay-yc.sh` вы получите URI вида:

```
vless://<UUID>@<YC_IP>:15443?type=tcp&security=reality&pbk=<PUBLIC_KEY>&fp=chrome&sni=yandex.ru&sid=<SHORT_ID>&spx=#YC-Relay
```

Актуальный URI сохраняется в `yc-relay-credentials.txt` в корне проекта.

**Важно:** при использовании preemptible VM IP может меняться каждые 24ч. После рестарта проверьте `yc-relay-credentials.txt` или запустите `rotate-relay-yc.sh`.

### Generic relay (Timeweb/VDSina)

После запуска `deploy-relay.sh` вы получите URI вида:

```
vless://<UUID>@<RELAY_IP>:443?type=tcp&security=reality&sni=www.gosuslugi.ru&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&flow=&encryption=none#Relay-Russia
```

Актуальный URI сохраняется в `/root/relay-credentials.txt` на relay VPS.

---

## Настройка по клиентам

### Hiddify (Windows)

1. Скопируйте VLESS URI
2. В Hiddify: **Добавить профиль** → **Импорт из буфера обмена**
3. Сервер `Relay-Russia` появится в списке
4. **Рекомендация**: включите **Auto Select** — Hiddify автоматически выберет рабочий сервер по ping

### Shadowrocket (iOS)

1. Скопируйте VLESS URI
2. В Shadowrocket: **+** → **Type: Subscribe** → вставьте URI
3. Или отсканируйте QR-код (сгенерируйте из URI на qr-code-generator.com)
4. **Для auto-failover**: создайте группу **URL Test**:
   - Нажмите **Proxy Groups** → **+**
   - Type: **url-test**
   - Добавьте все серверы (direct Reality, Cloudflare CDN, Relay)
   - URL: `http://www.gstatic.com/generate_204`
   - Interval: 300 секунд

### v2rayNG (Android)

1. Скопируйте VLESS URI
2. В v2rayNG: **+** → **Импорт конфигурации из буфера**
3. **Для auto-failover**:
   - Создайте **Subscription Group**
   - Добавьте все серверы
   - v2rayNG поддерживает **URL Test** группы с автопереключением

---

## Приоритет серверов

При настройке auto-failover группы, расставьте серверы в порядке приоритета:

| # | Сервер | Latency | Когда использовать |
|---|--------|---------|--------------------|
| 1 | reality-main (443, microsoft.com) | Минимальный | Всегда первый выбор |
| 2 | reality-google (8443, google.com) | Минимальный | Если 443 заблокирован |
| 3 | reality-apple (2053, apple.com) | Минимальный | Ещё один SNI |
| 4 | Cloudflare CDN (your-domain.com) | +20-50ms | Если IP заблокирован |
| 5 | **Relay-Russia** | +30-80ms | Если Cloudflare не работает |

---

## Проверка работоспособности

1. Подключитесь через Relay
2. Откройте https://2ip.ru — должен показать **шведский IP** (не российский!)
3. Откройте https://yandex.ru — должен работать **напрямую** (split routing)
4. Проверьте скорость: https://fast.com

## Troubleshooting

| Проблема | Решение |
|----------|---------|
| Не подключается к Relay | Проверить: `python ssh_exec.py -t relay status` |
| Показывает российский IP | Relay outbound не настроен — проверить config.json на relay |
| Медленная скорость | Нормально: +30-80ms из-за двойного хопа |
| Relay был забанен провайдером | Пересоздать VPS, перезапустить `deploy-relay.sh` |
