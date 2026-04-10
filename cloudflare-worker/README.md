# Cloudflare Worker — WebSocket Proxy for VLESS

A Cloudflare Worker that proxies WebSocket connections through Cloudflare CDN to a VLESS backend server. All non-matching requests see a generic "Coming Soon" page.

## How it works

```
Client (v2ray/xray) ──WSS 443──▶ Cloudflare CDN ──WS 2082──▶ VPS (VLESS)
```

1. Client connects to `your-worker.workers.dev:443` with WebSocket transport.
2. Cloudflare terminates TLS and the Worker forwards the WS connection to the backend VPS on port 2082.
3. All other visitors see a harmless landing page.

## Prerequisites

- Cloudflare account (free plan works)
- Node.js >= 18
- Wrangler CLI: `npm install -g wrangler`

## Deploy

```bash
cd cloudflare-worker

# Authenticate (one-time)
wrangler login

# Deploy
npx wrangler deploy
```

After deploying you will get a URL like `https://vpn-ws-proxy.<your-subdomain>.workers.dev`.

## Configuration

### Change the secret path (recommended)

Edit `wrangler.toml`:

```toml
[vars]
WS_PATH = "/your-random-string-here"
```

Generate a random path:

```bash
python3 -c "import secrets; print('/' + secrets.token_urlsafe(24))"
```

Then redeploy: `npx wrangler deploy`.

### Backend host/port

Adjust `BACKEND_HOST` and `BACKEND_PORT` in `wrangler.toml` if the VPS address changes.

## Client configuration

Configure your v2ray/xray/sing-box client:

| Field          | Value                                          |
|----------------|------------------------------------------------|
| Address        | `vpn-ws-proxy.<subdomain>.workers.dev`         |
| Port           | `443`                                          |
| Transport      | WebSocket                                      |
| WS Path        | Value of `WS_PATH` (e.g. `/ws-proxy`)          |
| TLS            | Enabled                                        |
| SNI            | Same as Address                                |
| VLESS UUID     | Your UUID configured on the VPS                |

## Using a custom domain

1. Add your domain to Cloudflare (DNS must be proxied, orange cloud).
2. In the Cloudflare dashboard go to **Workers & Pages > your worker > Settings > Domains & Routes**.
3. Add a route like `vpn.yourdomain.com/*`.
4. Update the client Address and SNI to `vpn.yourdomain.com`.

## Security notes

- **Change `WS_PATH`** to a long random string. The default `/ws-proxy` is just a placeholder.
- The path acts as a shared secret: only clients that know it can establish the proxy tunnel.
- The landing page is intentionally generic — it reveals nothing about the proxy.
- Backend IP is not exposed to clients; they only see the Cloudflare edge IP.
