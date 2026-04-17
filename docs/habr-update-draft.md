# Черновик UPDATE для статьи Habr 1021160

> Вставить в конец статьи «Мой VPN пережил белые списки» в виде отдельного блока **UPDATE**. Русский, форматирование под Habr (Markdown).

---

## UPDATE от 17 апреля 2026 — хардинг по фидбеку

Спасибо за комментарии — критика была по делу, часть претензий подтверждена, что-то пришлось переделывать. Отдельно спасибо [@paxlo](https://habr.com/ru/users/paxlo/), [@aax](https://habr.com/ru/users/aax/), [@sbanger3000](https://habr.com/ru/users/sbanger3000/), [@ice938](https://habr.com/ru/users/ice938/), [@SPNkd](https://habr.com/ru/users/SPNkd/), [@savagebk](https://habr.com/ru/users/savagebk/), [@Altair4717](https://habr.com/ru/users/Altair4717/) и [@mitya_k](https://habr.com/ru/users/mitya_k/) за свежую статью [«Как не передать на desktop свой IP в РКН»](https://habr.com/ru/articles/1023224/), которая вскрыла главную дыру в архитектуре.

### 1. Миграция с Aeza на VDSina (сделано до публикации, забыл написать)

`@478wo55bn4p987` прав — Aeza действительно удаляла VPS по требованию РКН и рассылала «письма счастья» пользователям (новость [habr.com/ru/news/973644](https://habr.com/ru/news/973644/)). Физическое расположение серверов в Швеции не спасает, пока юрлицо — российское. Переехал на **VDSina, Амстердам (Нидерланды)** — европейская юрисдикция, цена ~€2.1/мес, IP чистый, AS нероссийская.

### 2. IP-leak blocklist — главное изменение после статьи @mitya_k

Проблема, которую я не учёл: любая вкладка «стукачёвого» сайта или десктопное приложение через `fetch("https://api.ipify.org")` может вытащить выходной IP VPS и отправить в российский сервис. CORS не защищает — у `ifconfig.me`, `icanhazip.com`, `chatgpt.com/cdn-cgi/trace` в заголовках `access-control-allow-origin: *` (подтверждение от [@babqeen](https://habr.com/ru/users/babqeen/) в комментах к 1023224). Как только один такой пиксель проходит через VPS → IP в базе РКН.

Добавил block-правило в серверный xray routing и симметрично в клиентские конфиги (v2rayNG, Shadowrocket, Hiddify). Список из 17 доменов взял у [@bubyshka](https://habr.com/ru/users/bubyshka/) + добавил YouTube-ручку `redirector.googlevideo.com` по тезису [@babqeen](https://habr.com/ru/users/babqeen/):

```
ipify.org, ifconfig.{me,io,co}, icanhazip.com, ipinfo.io,
ipapi.co, ip-api.com, checkip.{amazonaws,dyndns}.com,
wtfismyip.com, my-ip.io, myexternalip.com, ipecho.net,
2ip.{io,ru}, redirector.googlevideo.com
```

Репо: [`client-configs/xray-server-routing.json`](https://github.com/<user>/VPN/blob/master/client-configs/xray-server-routing.json).

Ограничение: `chatgpt.com/cdn-cgi/trace` нельзя заблокировать на сервере — xray не матчит по URL-path, а хост нужен для самого ChatGPT. Решается только клиентски — uBlock Origin: `||chatgpt.com/cdn-cgi/trace$xhr`.

### 3. SNI rotation — ответ на критику @ice938 и @Barnaby

Тезис «VLESS Reality с чужим SNI `www.microsoft.com` на IP VDSina — очевидная аномалия» признаю справедливым. Сменить один захардкоженный SNI на свой домен — отдельная работа (ниже), а быстрый фикс — ротация: добавил в каждый Reality inbound несколько `serverNames`:

- inbound-443: `www.microsoft.com, microsoft.com, www.bing.com, azure.microsoft.com`
- inbound-8443: `dl.google.com, www.google.com, accounts.google.com, mail.google.com`
- inbound-2053: `www.apple.com, apple.com, www.icloud.com, support.apple.com`

Клиент в ClientHello показывает рандомный SNI из пула. Паттерн «один IP = один SNI 24/7» для DPI ломается. `dest` Reality остаётся один — куда Reality steals handshake.

### 4. Layer 0.5: nginx ssl_preread SNI-split со своим доменом (@ice938)

Рецепт из вашего комментария реализован отдельным deploy-скриптом [`deploy-sni-split.sh`](https://github.com/<user>/VPN/blob/master/deploy-sni-split.sh). Что делает:

1. Ставит nginx + certbot, выпускает Let's Encrypt для `xk127r.top`.
2. Поднимает статическую заглушку «Portfolio / Coming Soon» с basic_auth на `https://xk127r.top/`.
3. Переводит Reality inbound на loopback-порты (127.0.0.1:10443/10444/10453).
4. На внешнем 443 — nginx stream с `ssl_preread on` и `map $ssl_preread_server_name → backend`: трафик с `xk127r.top` идёт в заглушку, с `microsoft/google/apple.*` — в xray.

Итог: на внешнем IP VDSina стоит обычный сайт с обычным LE-сертификатом, а Reality нигде не торчит напрямую. Включаю по запросу, не в дефолте — если ТСПУ банит IP VDSina целиком (со всем хостингом), SNI-split не спасёт.

### 5. Миф «IP Yandex Cloud в белых списках ТСПУ» снят

Принял критику [@paxlo](https://habr.com/ru/users/paxlo/), [@aax](https://habr.com/ru/users/aax/) и [@Varpun](https://habr.com/ru/users/Varpun/): AS `Yandex.Cloud LLC` (пользовательские VM, подсети 51.250.x.x, 212.233.x.x) и AS `YANDEX LLC` (сервисы Яндекса) — разные автономные системы, ТСПУ фильтрует их раздельно. В ряде регионов YC-relay уже блокируется при активных белых списках. В документации [`docs/07-advanced-layers.md`](https://github.com/<user>/VPN/blob/master/docs/07-advanced-layers.md) этот тезис переведён в «пока работает, но ненадёжно», инфраструктура YC удалена в апреле 2026 — теперь Layer 2 использует generic VPS (Timeweb/VDSina/Selectel), с оговоркой что «IP в белых списках не гарантированно». Наблюдение [@s5384](https://habr.com/ru/users/s5384/) про токсичность YC-диапазонов в спам-базах тоже в тему — пытаться имитировать `SNI=ya.ru` с IP YC не имеет смысла.

### 6. Трёхзвенная relay-схема (@tequier0, @kinderbug)

Замечание [@kinderbug](https://habr.com/ru/users/kinderbug/): если выходная нода заблокирована, двухзвенная схема «RU-relay → RU-exit» не помогает. Уточнение [@tequier0](https://habr.com/ru/users/tequier0/): промежуточный узел должен быть **заграничным**, тогда блок выходной ноды не катастрофичен. Текущая архитектура: `Client → RU relay → VDSina (NL)` — двухзвенная. Добавил в [`client-configs/relay-config.md`](https://github.com/<user>/VPN/blob/master/client-configs/relay-config.md) раздел с инструкцией как превратить в трёхзвенную: `Client → RU relay → промежуточный EU VPS (RackNerd / BuyVM без KYC) → VDSina`. По умолчанию не включаю — это +€2-3/мес и +80 мс latency, включать если IP VDSina начнёт банить по принадлежности.

### 7. WireSock, Firefox containers, PAC-блок localhost — отдельным разделом docs

Спасибо [@enchained](https://habr.com/ru/users/enchained/), [@valera_efremov](https://habr.com/ru/users/valera_efremov/), [@alex_1065](https://habr.com/ru/users/alex_1065/), [@equeim](https://habr.com/ru/users/equeim/) за советы из 1023224 — все легли в [`docs/05-security.md`](https://github.com/<user>/VPN/blob/master/docs/05-security.md) раздел «Защита от деанона VPS-IP через IP-leak эндпоинты»:

- Per-tab routing в Firefox через Multi-Account Containers + FoxyProxy/SmartProxy/Containerise
- uBlock Origin → «Block Outsider Intrusion into LAN» против сканирования LAN с публичных сайтов
- PAC-скрипт [@alex_1065](https://habr.com/ru/users/alex_1065/) против сканирования `localhost:<socks-port>` из JS (`network.proxy.allow_hijacking_localhost=true`)
- [WireSock](https://www.wiresock.net/) как Windows-альтернатива v2rayN с app-based tunneling через WFP
- Список «рискованных» десктоп-приложений из 1023224 — не запускать на одной машине с VPN

### 8. Что НЕ делал и почему

- **Не уходил с VLESS Reality полностью** на AmneziaWG/Shadowsocks (@Barnaby, @iamkisly). Reality всё ещё отлично работает на домашнем Wi-Fi; AmneziaWG 2.0 и BAREBONE2022 добавлены в [docs/07-advanced-layers.md](https://github.com/<user>/VPN/blob/master/docs/07-advanced-layers.md) как опции на будущее.
- **Не отказался от Cloudflare fronting** как layer 1 — он заблокирован на мобильных через белые списки, но на домашнем LTE/Wi-Fi работает.
- **Статья не нейрослоп** в том смысле, в котором подразумевали [@arsmerk777](https://habr.com/ru/users/arsmerk777/) и [@sbanger3000](https://habr.com/ru/users/sbanger3000/). Да, код и скрипты писаны с помощью Claude Code, да, архитектура сначала была сырой. Фидбек принял, переделал — это и есть process, не «накопи GPT‑слоп и опубликуй».

### Где посмотреть изменения

GitHub: ссылка на коммит с тегом `hardening-2026-04-17`.

Скрипт проверки, что блок-лист работает:

```bash
# Запустить с клиента через активный VPN
bash check-ip-leaks.sh
# ожидаем: все 17 leak-эндпоинтов → [BLOCK], контрольные google/cloudflare → [OK]
```

Если найдёте ещё дыры — велкам в комменты.

---

**TL;DR для читателя статьи**: после критики серверный xray теперь дропает запросы на 17 «узнай-свой-IP» эндпоинтов, SNI ротируется по пулу из 4 вариантов на каждый inbound, есть опциональный nginx-слой со своим доменом и Let's Encrypt для максимальной легитимности, тезис про «YC в белых списках» снят.
