/**
 * Cloudflare Worker — WebSocket proxy for VLESS over Cloudflare CDN.
 *
 * Proxies WebSocket connections from clients to the backend VPS.
 * All non-matching requests receive a harmless landing page.
 *
 * Environment variables (set in wrangler.toml or dashboard):
 *   BACKEND_HOST  — VPS IP or hostname  (default: YOUR_VPS_IP)
 *   BACKEND_PORT  — VLESS WS inbound port (default: 2082)
 *   WS_PATH       — secret path to match  (default: /ws-proxy)
 */

const LANDING_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Site Under Construction</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen,Ubuntu,sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;
         background:#f5f5f5;color:#333}
    .container{text-align:center;padding:2rem}
    h1{font-size:2rem;margin-bottom:.5rem}
    p{color:#666;margin-bottom:1.5rem}
    .bar{width:200px;height:4px;background:#ddd;border-radius:2px;margin:0 auto;overflow:hidden}
    .bar span{display:block;width:40%;height:100%;background:#4a90d9;border-radius:2px;
              animation:slide 1.5s ease-in-out infinite}
    @keyframes slide{0%{transform:translateX(-100%)}100%{transform:translateX(350%)}}
    footer{margin-top:2rem;font-size:.75rem;color:#aaa}
  </style>
</head>
<body>
  <div class="container">
    <h1>Coming Soon</h1>
    <p>We are working hard to bring you something amazing. Stay tuned!</p>
    <div class="bar"><span></span></div>
    <footer>&copy; 2024 All rights reserved.</footer>
  </div>
</body>
</html>`;

export default {
  /**
   * Main fetch handler.
   *
   * @param {Request}  request
   * @param {Object}   env      — bound environment variables
   * @returns {Response}
   */
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      const secretPath = env.WS_PATH || '/ws-proxy';

      // ── Only proxy on the secret path ────────────────────────────
      if (url.pathname !== secretPath) {
        return landingPage();
      }

      // ── Require WebSocket upgrade ────────────────────────────────
      const upgradeHeader = request.headers.get('Upgrade');
      if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
        return new Response('Expected Upgrade: websocket', { status: 426 });
      }

      // ── Build backend URL ────────────────────────────────────────
      const backendHost = env.BACKEND_HOST || 'YOUR_VPS_IP';
      const backendPort = env.BACKEND_PORT || '2082';

      const backendUrl = new URL(request.url);
      backendUrl.hostname = backendHost;
      backendUrl.port = backendPort;
      // Backend speaks plain WS; Cloudflare terminates TLS on the edge.
      backendUrl.protocol = 'http:';

      // ── Forward the request (Cloudflare relays the WS automatically) ─
      const backendRequest = new Request(backendUrl.toString(), {
        method: request.method,
        headers: request.headers,
        body: request.body,
      });

      const response = await fetch(backendRequest);
      return response;
    } catch (err) {
      console.error('Worker error:', err);
      // Return landing page on any unexpected error to avoid leaking info.
      return landingPage(500);
    }
  },
};

/**
 * Returns the fake landing page response.
 *
 * @param {number} status  HTTP status code (default 200)
 * @returns {Response}
 */
function landingPage(status = 200) {
  return new Response(LANDING_HTML, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}
