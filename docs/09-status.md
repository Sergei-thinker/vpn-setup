# 9. Текущий статус

## Реализовано (Layer 0 — прямое подключение)
- [x] VPS (EU, KVM, Debian 12, ~$2-5/мес)
- [x] VLESS Reality на порту 443 (SNI: microsoft.com)
- [x] BBR + TCP-тюнинг
- [x] DNS (1.1.1.1, DoH)
- [x] Nginx-камуфляж
- [x] SSH на нестандартном порту, UFW, fail2ban
- [x] Клиент Windows (Hiddify 4.1.1)
- [x] Клиент iOS (v2RayTun, фрагментация 100-400)
- [x] ulimit 65535, Xray v26.3.27
- [x] Фикс краша XtlsPadding (flow отключён)

## Реализовано (Layer 1 — Relay через российский VPS)
- [x] Relay inbound на основном VPS (порт 10443, VLESS xHTTP Reality)
- [x] `deploy-relay.sh` — полная автоматизация для generic RU VPS (Timeweb/VDSina/Selectel/VK Cloud)
- [x] Xray relay: порт 443, VLESS Reality, SNI: gosuslugi.ru
- [x] Мониторинг через `monitor-relay.sh` (проверка обоих VPS)
- [x] Тест E2E: клиент → RU relay → основной VPS → 2ip.ru показывает зарубежный IP

> **Важно:** Cloudflare активно блокируется ТСПУ с середины 2025. Layer 3 (Cloudflare) не работает при белых списках на мобильной сети. Layer 1 через российский generic VPS — единственный практический метод обхода белых списков.
>
> **Yandex Cloud удалён 2026-04-17**: по критике @paxlo/@aax/@Varpun в [комментах к Habr 1021160](https://habr.com/ru/articles/1021160/), AS `Yandex.Cloud LLC` ≠ AS `YANDEX LLC`, YC-VM блокируется при активных белых списках — тезис про «IP YC в белых списках ТСПУ» опровергнут. Скрипты `deploy-relay-yc.sh`/`rotate-relay-yc.sh`/`yc-cloud-init.yaml.tpl` удалены.

## Реализовано (Layer 3 — Cloudflare CDN)
- [x] Домен `your-domain.com` (Namecheap)
- [x] Cloudflare DNS + Proxy ON
- [x] Worker `vpn-ws-proxy` задеплоен
- [x] Worker route `your-domain.com/*`
- [x] Shadowrocket для iOS куплен и настроен
- [x] Split routing (shadowrocket-rules.conf, 150+ RU доменов)

## Подготовлено (скрипты и конфиги)
- [x] `deploy-multilayer.sh` — развёртывание backup inbound-ов и мониторинга
- [x] `quick-rebuild.sh` — disaster recovery с нуля
- [x] `ssh_exec.py` — SSH-утилита (SSH-ключи, dual-VPS, relay-status)
- [x] `cloudflare-worker/` — Worker для CDN-фронтинга
- [x] `client-configs/` — split routing для всех платформ
- [x] `deploy-relay.sh` — fallback relay для generic VPS (Timeweb и т.д.)

## Ожидает выполнения (по приоритету)

**P1 — Клиенты:**
- [ ] Настроить Android (v2rayNG) — импорт subscription
- [ ] Включить auto-select/failover в клиентах

**P2 — Layer 1 доработки:**
- [ ] Протестировать Layer 1 на мобильной сети при белых списках (МТС/Мегафон)
- [ ] Арендовать backup VPS (другой провайдер, fallback)

**P3 — Аварийная готовность (Layer 2 — OlcRTC):**
- [x] Исследование OlcRTC завершено (статья Habr от 7 апреля 2026)
- [ ] Протестировать OlcRTC на Linux-машине (или WSL2)
- [ ] Следить за ECH в Xray-core

## Бюджет

| Статья | Стоимость | Фаза |
|--------|-----------|------|
| VPS (EU, KVM) | ~$2-5/мес | 0 |
| RU relay VPS (Timeweb/VDSina) | ~80-100 RUB/мес (~$1) | 1 |
| Backup VPS (опц.) | 2-5 EUR/мес | 1 |
| Домен (Namecheap) | ~$6/год (первый год ~$3) | 3 |
| Cloudflare | 0 EUR | 3 |
| Shadowrocket iOS | $2.99 разово | 0 |
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
