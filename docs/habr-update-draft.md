# Черновик UPDATE для статьи Habr 1021160

> Вставить в конец статьи отдельным блоком.

---

## UPDATE 17 апреля 2026

Спасибо за критику. По мотивам статьи [@mitya_k про IP-leak на desktop](https://habr.com/ru/articles/1023224/) добавил серверный блок на 17 «узнай-свой-IP» эндпоинтов (`ipify.org`, `ifconfig.me`, `icanhazip.com`, `2ip.*`, `redirector.googlevideo.com` и др.) — раньше любая вкладка или десктоп-приложение могли через `fetch()` слить IP VPS в РКН. Сделал SNI rotation: теперь по 4 `serverNames` на каждый Reality inbound вместо одного, паттерн «IP ↔ один SNI» для DPI ломается. Убрал Yandex Cloud relay — тезис «IP YC в белых списках ТСПУ» оказался мифом: AS `Yandex.Cloud LLC` и AS `YANDEX LLC` — разные автономные системы, YC-VM спокойно режется при белых списках. Мигрировал с Aeza на VDSina (Амстердам) — Aeza по требованию РКН удаляла VPS. Плюс готовый опциональный `deploy-sni-split.sh` со своим доменом + nginx/Let's Encrypt, если базовый Reality начнут детектить. Код и новые разделы документации — [github.com/Sergei-thinker/vpn-setup](https://github.com/Sergei-thinker/vpn-setup).
