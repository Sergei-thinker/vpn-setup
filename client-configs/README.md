# Split Routing Client Configurations

Split routing (split tunneling) directs Russian services through a direct connection while routing all other traffic through the VPN proxy. This provides two benefits:

1. **Russian services work correctly** -- banking apps, government portals, and local services that may block foreign IPs continue to function normally.
2. **International services bypass restrictions** -- everything else goes through the VPN as expected.

---

## Files in This Directory

| File | Platform | Purpose |
|------|----------|---------|
| `shadowrocket-rules.conf` | iOS (Shadowrocket) | Client-side rule-based routing |
| `v2rayng-routing.json` | Android (v2rayNG) | Client-side custom routing rules |
| `hiddify-routing.txt` | Windows/Android (Hiddify) | Instructions and domain lists for Hiddify |
| `xray-server-routing.json` | Server (3X-UI) | Server-side routing applied to all clients |

---

## Option A: Server-Side Routing (Recommended)

Server-side routing is applied once and affects **all connected clients** regardless of their app. This is the simplest approach.

### Setup in 3X-UI Panel

1. Log in to the 3X-UI admin panel
2. Go to **Xray Settings** (left sidebar)
3. Open the **Routing** tab
4. Replace the existing routing configuration with the contents of `xray-server-routing.json`
5. Click **Save** and then **Restart Xray**

The server uses `geosite:category-ru` and `geoip:ru` databases that are maintained by the Xray community and cover most Russian domains and IP ranges.

### Verify it works

After applying, test from a connected client:
- Open https://2ip.ru -- should show your **real Russian IP**
- Open https://whatismyipaddress.com -- should show the **VPN server IP**

---

## Option B: Client-Side Routing

Client-side routing gives each user control over their own rules. This is useful when you cannot modify the server configuration, or when different users need different routing policies.

---

### iOS -- Shadowrocket

1. Transfer `shadowrocket-rules.conf` to your iPhone (AirDrop, iCloud, or any file method)
2. Open **Shadowrocket**
3. Tap the **Config** tab (bottom bar)
4. Tap **+** in the top right -> **Import from file** or **Download from URL**
   - If hosting the file, use a direct URL to the raw `.conf` file
5. Select the imported config (it appears in the list)
6. Tap **Use Config**
7. Go back to the **Home** tab, select your proxy server, and connect

**Alternative: Manual rule entry**
1. Go to **Config** -> tap your active config -> **Edit Config**
2. Under the **[Rule]** section, add rules from the file manually
3. The most important rules are `GEOIP,RU,DIRECT` and `FINAL,PROXY`

**Testing:**
- Visit https://2ip.ru in Safari -- should show your Russian IP
- Visit https://ifconfig.me -- should show the VPN server IP

---

### Android -- v2rayNG

1. Transfer `v2rayng-routing.json` to your Android device
2. Open **v2rayNG**
3. Tap the menu icon (three dots, top right) -> **Settings**
4. Scroll to **Custom routing** and tap on it
5. Select **Custom Rules** mode
6. Tap **Direct URL or IP** and add the domain list
   - Alternatively, import the JSON as a routing ruleset

**Manual method (simpler):**
1. Open v2rayNG -> **Settings** -> **Routing Settings**
2. Set routing mode to **Custom**
3. In the **Direct** field, paste:
   ```
   geosite:category-ru
   geoip:ru
   geoip:private
   domain:yandex.ru
   domain:sberbank.ru
   domain:gosuslugi.ru
   domain:vk.com
   domain:mail.ru
   domain:ozon.ru
   domain:wildberries.ru
   ```
   (Add more domains from the JSON file as needed)
4. Leave **Proxy** field as default (everything)
5. Save and reconnect

**Testing:**
- Open https://2ip.ru in browser -- should show Russian IP
- Open https://ifconfig.me -- should show VPN server IP

---

### Windows/Android -- Hiddify

1. Open **Hiddify** -> **Settings** -> **Config Options**
2. Go to **Routing** section
3. Set **Routing Mode** to **Custom**
4. Configure DNS:
   - **Remote DNS**: `https://1.1.1.1/dns-query`
   - **Direct DNS**: `https://77.88.8.8/dns-query` (Yandex DNS)
5. In **Direct domains**, paste the domain list from `hiddify-routing.txt`
   - Use the comma-separated format at the bottom of the file for single-line input
6. In **Direct IPs**, enter: `geoip:ru, geoip:private`
7. Save and reconnect

**Testing:**
- Open https://2ip.ru -- Russian IP should appear
- Open https://ifconfig.me -- VPN server IP should appear

---

## How It Works

```
User Device
    |
    |--- Request for yandex.ru -----> DIRECT (no VPN) -----> yandex.ru
    |
    |--- Request for google.com ----> VPN PROXY -----------> google.com
    |
    |--- Request for gosuslugi.ru --> DIRECT (no VPN) -----> gosuslugi.ru
    |
    |--- Request for youtube.com ---> VPN PROXY -----------> youtube.com
```

**Domain matching**: The client (or server) checks each outgoing request against the rule list. If the domain matches a Russian service, it routes directly. Everything else goes through the encrypted VPN tunnel.

**GeoIP matching**: For IP addresses not matched by domain rules, the `geoip:ru` database identifies Russian IP ranges and routes them directly. The `geoip:private` rule ensures local network traffic (192.168.x.x, 10.x.x.x) never goes through the VPN.

**domainStrategy: IPIfNonMatch**: When a domain is not matched by any domain rule, Xray resolves it to an IP address and then checks the IP rules. This catches Russian services that use uncommon domain names.

---

## Updating Domain Lists

Russian services change domains periodically. To update:

1. **Server-side** (`geosite:category-ru`): Update the geosite database in 3X-UI. Go to Xray Settings and click "Update Geo Files."
2. **Client-side**: Add new domains to the relevant config file and re-import.

Common additions to watch for:
- Banks rebranding (e.g., Tinkoff -> T-Bank at tbank.ru)
- New marketplace domains
- CDN domains used by Russian services

---

## Layer 1 — Подключение через Relay (российский VPS)

Если прямое подключение к шведскому VPS и Cloudflare CDN заблокированы, используется relay через российский VPS. В этом режиме клиент подключается к VPS в РФ, а тот пересылает трафик на шведский VPS через xHTTP.

Подробная инструкция по настройке клиента для работы через relay: **[relay-config.md](relay-config.md)**

Краткий порядок действий:
1. Получить VLESS-ссылку для relay (генерируется `deploy-relay.sh`)
2. Импортировать в клиент (Hiddify, Shadowrocket, v2rayNG)
3. Адрес подключения — IP российского VPS, порт 443
4. Split routing работает так же, как при прямом подключении

---

## Troubleshooting

**Russian site shows VPN IP instead of real IP:**
- The domain is missing from the direct list. Add it and reconnect.
- If using server-side routing, check that geosite/geoip databases are up to date.

**International site is not going through VPN:**
- Check that `FINAL,PROXY` (Shadowrocket) or the catch-all proxy rule exists.
- Ensure the VPN connection is active.

**Banking app refuses to work:**
- Some banking apps use certificate pinning and detect VPN connections.
- Ensure the bank's domain AND its CDN domains are in the direct list.
- Try adding the bank's IP range to direct IPs.

**DNS leaks:**
- Use DoH (DNS over HTTPS) in both remote and direct DNS settings.
- Remote DNS: `https://1.1.1.1/dns-query` (for proxied traffic)
- Direct DNS: `https://77.88.8.8/dns-query` (Yandex, for Russian traffic)
