# Черновик UPDATE для статьи Habr 1021160

> Вставить в конец статьи отдельным блоком. Русский, Markdown под Habr.

---

## UPDATE 17 апреля 2026 — что поправил по комментариям

Спасибо за критику — по делу. Основное изменение спровоцировала свежая статья [@mitya_k «Как не передать на desktop свой IP в РКН»](https://habr.com/ru/articles/1023224/), там ключевая дыра в split tunneling, которую я не учёл.

**1. IP-leak blocklist.** Любая вкладка «стукачёвого» сайта или десктопное приложение может через `fetch("https://api.ipify.org")` вытащить IP VPS и отдать в РКН. CORS не спасает. Добавил серверный xray-блок на 17 таких доменов (`ipify.org`, `ifconfig.{me,io,co}`, `icanhazip.com`, `ipinfo.io`, `2ip.*`, `redirector.googlevideo.com` и др.) + симметрично в клиентские конфиги. Запрос к ним теперь дропается в blackhole, проверяется скриптом `check-ip-leaks.sh`.

**2. SNI rotation.** Справедливое замечание — `SNI=www.microsoft.com` на IP хостинга выглядит аномально. В каждом Reality inbound теперь 4 `serverNames` вместо одного: microsoft/bing/azure, google/accounts/mail, apple/icloud. Паттерн «один IP = один SNI навсегда» для DPI ломается, существующие клиентские ссылки продолжают работать.

**3. Свой домен + nginx SNI-split (опция).** Добавил `deploy-sni-split.sh`: nginx + Let's Encrypt на `xk127r.top` со статической заглушкой и basic_auth, Reality ушёл на loopback. Внешне IP выглядит как обычный хостинг сайта. По умолчанию не включаю — если базовый Reality задетектят, можно докатить.

**4. Yandex Cloud relay убрал.** Тезис «IP YC в белых списках ТСПУ» — это миф. AS `Yandex.Cloud LLC` (пользовательские VM) и AS `YANDEX LLC` (сервисы Яндекса) — разные автономные системы, ТСПУ фильтрует их раздельно, YC-VM уже блокируется при активных белых списках. Скрипты удалены, Layer 1 — только generic RU VPS (Timeweb/VDSina/Selectel).

**5. Aeza → VDSina (Амстердам).** Aeza действительно удаляла VPS по требованию РКН. Мигрировал до публикации, забыл упомянуть в статье.

**Изменения в репо:** [github.com/Sergei-thinker/vpn-setup](https://github.com/Sergei-thinker/vpn-setup) — смотрите коммит `0eac332` и новые разделы в `docs/05-security.md` про per-tab routing (Firefox containers + FoxyProxy), WireSock и блок сканирования localhost из JS.

Если найдёте ещё дыры — пишите.
