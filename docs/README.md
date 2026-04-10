# Документация VPN-инфраструктуры

Полная документация личного VPN на базе VLESS Reality + Cloudflare CDN.

## Содержание

| # | Документ | Описание |
|---|----------|----------|
| 1 | [Обзор](01-overview.md) | Зачем нужен свой VPN, как работают блокировки в РФ, выбор VLESS Reality |
| 2 | [Архитектура](02-architecture.md) | 4-уровневая защита, матрица inbound-ов, компоненты |
| 3 | [Настройка сервера](03-server-setup.md) | Аренда VPS, установка 3X-UI, конфигурация VLESS Reality |
| 4 | [Настройка клиентов](04-client-setup.md) | Windows (Hiddify), iOS (Shadowrocket), Android (v2rayNG) |
| 5 | [Безопасность](05-security.md) | Hardening, firewall, оптимизация для мобильных сетей |
| 6 | [Split routing](06-split-routing.md) | Российские сайты напрямую, конфиги для всех платформ |
| 7 | [Продвинутые уровни](07-advanced-layers.md) | CDN Cloudflare, Relay через РФ VPS, аварийные методы |
| 8 | [Обслуживание](08-operations.md) | Мониторинг, troubleshooting, disaster recovery |
| 9 | [Статус](09-status.md) | Текущий статус проекта, бюджет, источники |

## Связанная документация

- [client-configs/README.md](../client-configs/README.md) — настройка split routing в клиентах
- [cloudflare-worker/README.md](../cloudflare-worker/README.md) — деплой Cloudflare Worker
- [DEVELOPMENT_LOG.md](../DEVELOPMENT_LOG.md) — хронологический лог разработки
