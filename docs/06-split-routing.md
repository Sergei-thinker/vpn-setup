# 6. Split routing — российские сайты напрямую

## Зачем
Без split routing весь трафик идёт через Швецию:
- Российские сайты медленнее (трафик летит в Стокгольм и обратно)
- Банки/Госуслуги могут блокировать шведский IP
- Yandex/VK показывают капчи

## Принцип
- **Российские домены и IP** -> DIRECT (минуя VPN)
- **Всё остальное** -> через VLESS Reality (VPN)

## Конфигурационные файлы

Готовые конфиги в папке `client-configs/`:

| Файл | Платформа | Формат |
|------|-----------|--------|
| `shadowrocket-rules.conf` | iOS (Shadowrocket) | Shadowrocket rules |
| `v2rayng-routing.json` | Android (v2rayNG) | Xray routing JSON |
| `hiddify-routing.txt` | Windows (Hiddify) | Инструкции + правила |
| `xray-server-routing.json` | Сервер (3X-UI) | Xray routing config |

Подробные инструкции: [client-configs/README.md](../client-configs/README.md)

## Серверный routing (3X-UI)

В 3X-UI -> Xray Settings -> Routing, вставить содержимое `xray-server-routing.json`:
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

Для работы нужны geosite/geoip базы:
```bash
wget -O /usr/local/x-ui/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget -O /usr/local/x-ui/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
```

## Клиентский routing

**iOS (Shadowrocket)** — лучший вариант:
1. Config -> Import -> URL -> указать путь к `shadowrocket-rules.conf`
2. Или вручную: Rules -> Add Rule -> DOMAIN-SUFFIX -> yandex.ru -> DIRECT

**Android (v2rayNG)**:
1. Settings -> Routing -> Custom Rules
2. Импортировать `v2rayng-routing.json`

**Windows (Hiddify)**:
1. Settings -> Routing -> Custom
2. Добавить домены из `hiddify-routing.txt` в Direct
