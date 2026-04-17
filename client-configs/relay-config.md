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

---

## Трёхзвенная схема (опционально, для повышенной анонимности)

Источник рекомендации: `@tequier0` в комментах к [habr 1021160](https://habr.com/ru/articles/1021160/) и ответ `@mitya_k` в [1023224](https://habr.com/ru/articles/1023224/): «заграничный промежуточный → на блок выходной ноды наплевать». Критика `@kinderbug`: если выходная нода заблокирована РКН, двухзвенная схема «RU-relay → RU-exit» не спасает.

### Схема

```
Клиент
  → RU relay VPS:443        (VLESS Reality, SNI: gosuslugi.ru)
    [IP российского провайдера — проходит белые списки]
  → промежуточный VPS (EU/SE):10443   (VLESS xHTTP Reality)
    [непроводной промежуток, ломает трассировку]
  → выходной VPS (NL/SE)              (VLESS Reality outbound)
    [реальный выход в интернет]
```

Стандартная архитектура проекта **двухзвенная**: `Client → RU relay → foreign VPS → Internet`. Для трёхзвенной схемы добавляется ещё один zagraniчный узел между RU и выходным.

### Когда включать

- **Не нужно**: обычная работа, нет признаков блокировок выходной ноды.
- **Нужно**: РКН заблокировал IP выходного VPS целиком; требуется независимость от одного выходного IP; параноидальный сценарий «кто владеет промежуточным, тот видит клиента».

### Как добавить третий хоп

На уже работающей двухзвенной схеме (после [deploy-relay.sh](../deploy-relay.sh)):

1. Арендовать третий VPS (EU, SE, DE) — промежуточный хоп. Любой generic провайдер без KYC: RackNerd, BuyVM, Scaleway.
2. На третьем VPS установить xray-core и настроить inbound VLESS xHTTP Reality (копия шведского relay из [deploy-relay-sweden.sh](../deploy-relay-sweden.sh)).
3. На RU relay в `deploy-relay.sh` заменить `outbound` — вместо `address: <SWEDEN_VPS_IP>` указать `address: <MIDDLE_EU_VPS_IP>`.
4. На промежуточном VPS настроить outbound обратно на выходной VPS с VLESS Reality outbound.

### Предостережения

- **Latency**: +30-80 мс на каждый дополнительный хоп (итого до +160 мс).
- **Стоимость**: ещё один VPS (~€2-3/мес).
- **Доверие**: промежуточный провайдер видит зашифрованный трафик, но знает source IP (RU-relay). Выбирайте провайдера без KYC, оплата крипто.
- **Рекомендация `@sloww`**: брать VPS с **лимитом трафика** (1-2 ТБ/мес) — VPN-«бизнесмены» не берут такие, и IP меньше выжигается спамом.
