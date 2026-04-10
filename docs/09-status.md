# 9. Текущий статус

## Реализовано (Layer 0 — прямое подключение)
- [x] VPS Aeza, Швеция, 1.99 EUR/мес
- [x] VLESS Reality на порту 443 (SNI: microsoft.com)
- [x] BBR + TCP-тюнинг
- [x] DNS (1.1.1.1, DoH)
- [x] Nginx-камуфляж
- [x] SSH на нестандартном порту, UFW, fail2ban
- [x] Клиент Windows (Hiddify 4.1.1)
- [x] Клиент iOS (v2RayTun, фрагментация 100-400)
- [x] ulimit 65535, Xray v26.3.27
- [x] Фикс краша XtlsPadding (flow отключён)

## Реализовано (Layer 1 — Cloudflare CDN)
- [x] Домен `your-domain.com` (Namecheap)
- [x] Cloudflare DNS + Proxy ON
- [x] Worker `vpn-ws-proxy` задеплоен
- [x] Worker route `your-domain.com/*`
- [x] Shadowrocket для iOS куплен и настроен
- [x] Split routing (shadowrocket-rules.conf, 150+ RU доменов)

## Реализовано (Layer 2 — Relay через Yandex Cloud)
- [x] Relay inbound на шведском VPS (порт 10443, VLESS xHTTP Reality)
- [x] VM в Yandex Cloud: `vpn-relay` (IP: <YOUR_RELAY_IP>, preemptible)
- [x] Xray relay: порт 15443, VLESS Reality, SNI: yandex.ru
- [x] Nginx декой на порту 80/443
- [x] `deploy-relay-yc.sh` — провизия через `yc` CLI + cloud-init
- [x] `rotate-relay-yc.sh` — авто-рестарт preemptible VM
- [x] `yc-status` команда в `ssh_exec.py`
- [x] Тест E2E: клиент → YC relay → Sweden → 2ip.ru показывает шведский IP

> **Важно:** Cloudflare активно блокируется ТСПУ с середины 2025. Layer 1 не работает при белых списках на мобильной сети. Layer 2 через Yandex Cloud — основной метод обхода белых списков.

## Подготовлено (скрипты и конфиги)
- [x] `deploy-multilayer.sh` — развёртывание backup inbound-ов и мониторинга
- [x] `quick-rebuild.sh` — disaster recovery с нуля
- [x] `ssh_exec.py` — SSH-утилита (SSH-ключи, dual-VPS, yc-status)
- [x] `cloudflare-worker/` — Worker для CDN-фронтинга
- [x] `client-configs/` — split routing для всех платформ
- [x] `deploy-relay.sh` — fallback relay для generic VPS (Timeweb и т.д.)

## Ожидает выполнения (по приоритету)

**P1 — Клиенты:**
- [ ] Настроить Android (v2rayNG) — импорт subscription
- [ ] Включить auto-select/failover в клиентах

**P2 — Layer 2 доработки:**
- [ ] Протестировать Layer 2 на мобильной сети при белых списках (МТС/Мегафон)
- [ ] Настроить `rotate-relay-yc.sh` в cron на Swedish VPS
- [ ] Рассмотреть статический IP (если IP меняется слишком часто, +100 RUB/мес)
- [ ] Арендовать backup VPS (другой провайдер, fallback)

**P3 — Аварийная готовность (Layer 3 — OlcRTC):**
- [x] Исследование OlcRTC завершено (статья Habr от 7 апреля 2026)
- [ ] Протестировать OlcRTC на Linux-машине (или WSL2)
- [ ] Следить за ECH в Xray-core

## Бюджет

| Статья | Стоимость | Фаза |
|--------|-----------|------|
| VPS Aeza (текущий) | 1.99 EUR/мес | 0 |
| Домен (Namecheap) | ~$6/год (первый год ~$3) | 1 |
| Cloudflare | 0 EUR | 1 |
| Shadowrocket iOS | $2.99 разово | 1 |
| Backup VPS (опц.) | 2-5 EUR/мес | 2 |
| Yandex Cloud relay (preemptible) | ~400 RUB/мес (~4 EUR) | 2 |
| **Минимум** | **~2 EUR/мес** | |
| **Максимум** | **~8 EUR/мес** | |

---

## Источники

- [Habr: История блокировок в РФ — ТСПУ, DPI, белые списки (2026)](https://habr.com/ru/articles/1014038/)
- [Habr: OlcRTC — обход белых списков через WebRTC Яндекс.Телемоста (2026)](https://habr.com/ru/articles/1020114/)
- [Habr: Белые списки и обход DPI (2026)](https://habr.com/ru/articles/1013122/)
- [Habr: Инструкция по быстрой настройке VPS и VLESS](https://habr.com/ru/articles/995542/)
- [Habr: Гайд по обходу белых списков и настройке цепочки](https://habr.com/en/articles/990206/)
- [Habr: Установка VPN с VLESS и Reality](https://habr.com/en/articles/990128/)
- [Habr: VLESS+Reality и Multi-hop архитектура](https://habr.com/ru/articles/926786/)
- [GitHub: OlcRTC — WebRTC туннель](https://github.com/zarazaex69/olcRTC)
- [GitHub: Configure-Xray-with-VLESS-Reality-on-VPS-server](https://github.com/EmptyLibra/Configure-Xray-with-VLESS-Reality-on-VPS-server)
- [GitHub: VPN configs for Russia](https://github.com/igareck/vpn-configs-for-russia)
- [Hiddify — кроссплатформенный клиент](https://hiddify.com/)
- [3X-UI — панель управления Xray](https://github.com/mhsanaei/3x-ui)
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
