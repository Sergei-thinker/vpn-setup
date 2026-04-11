# v2rayN — настройка для Windows

v2rayN — рекомендуемый Windows-клиент для VLESS Reality VPN. Использует тот же Xray-core, что и сервер 3X-UI. Имеет встроенный пресет маршрутизации для России.

GitHub: https://github.com/2dust/v2rayN

---

## Установка

1. Скачать последнюю стабильную версию: [v2rayN Releases](https://github.com/2dust/v2rayN/releases)
   - Файл: `v2rayN-windows-64.zip`
2. Распаковать в папку (например, `C:\v2rayN`)
3. **Запустить `v2rayN.exe` от имени администратора** (правый клик → Run as Administrator)
   - Администратор нужен для TUN-режима

> При первом запуске Windows Defender может показать предупреждение — разрешить.

---

## Импорт подписки

1. В панели 3X-UI скопировать subscription link:
   - Inbound → reality-xxx → Actions → Export → Subscription URL
2. В v2rayN: **Подписки → Добавить подписку**
3. Вставить URL подписки → OK
4. **Ctrl+U** — обновить подписку
5. В списке появится профиль VLESS Reality

---

## Настройка TUN-режима

**TUN обязателен!** Без него QUIC/UDP трафик утекает мимо VPN.

1. Settings → TUN Mode → **включить**
2. Stack: **Mixed** (рекомендуется) или **gVisor**
3. Перезапустить v2rayN

После включения TUN в трее появится иконка сетевого адаптера — весь трафик (TCP + UDP + DNS) теперь идёт через VPN.

---

## Split routing — пресет "Россия"

Российские сайты (банки, Госуслуги, Яндекс, VK) должны идти напрямую, минуя VPN.

1. Settings → Regional Presets → **Russia**
2. v2rayN автоматически подтянет правила из `runetfreedom/russia-v2ray-rules-dat`:
   - `geosite:ru-blocked` — заблокированные в РФ сайты → через VPN
   - `geosite:ru-available-only-inside` — российские сервисы → напрямую
3. Сохранить и переподключиться

> Альтернативно, можно настроить маршрутизацию вручную:
> Settings → Routing Settings → добавить правила из `xray-server-routing.json`

---

## Подключение

1. Выбрать сервер в списке (reality-xxx)
2. Нажать кнопку **подключения** (или Enter)
3. В трее — иконка v2rayN, статус "Connected"

---

## Проверка

После подключения проверить что утечек нет:

| Тест | URL | Ожидание |
|------|-----|----------|
| IP | https://2ip.ru | Швеция (SE) |
| DNS leak | https://browserleaks.com/dns | Не российские DNS |
| WebRTC | https://browserleaks.com/webrtc | Нет реального IP |
| Cloudflare | https://www.cloudflare.com/cdn-cgi/trace | `loc=SE` |
| Google | https://google.com | Работает, не блокирует |
| Claude | https://claude.ai | Доступен |

---

## Troubleshooting

### TUN не работает
- Убедиться что запущен **от администратора**
- Проверить что антивирус не блокирует TUN-адаптер
- Попробовать Stack: `gVisor` вместо `Mixed`
- Обновить v2rayN до последней версии

### Google/Claude думают что я в России
- Проверить что TUN включён (в трее должен быть значок сетевого адаптера)
- Запустить тесты утечек из таблицы выше
- Если `browserleaks.com/dns` показывает российские DNS — TUN не работает
- Очистить cookies Google и Claude (кэшированная геолокация)

### Медленная скорость
- Settings → Core Type → **Xray** (не sing-box)
- Убедиться что BBR включён на сервере (`python ssh_exec.py exec "sysctl net.ipv4.tcp_congestion_control"`)
- Попробовать другой сервер из подписки (если есть несколько inbound-ов)

### Российские сайты не работают
- Проверить что пресет "Russia" включён
- Или добавить домен вручную: Settings → Routing → Add Rule → Domain → `domain:example.ru` → Direct
