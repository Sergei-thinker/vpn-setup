---
name: vpn-troubleshoot
description: "VPN troubleshooting decision tree. Use when user reports VPN problems: 'VPN not working', 'can't connect', 'stopped working', 'no internet through VPN', 'slow VPN', 'troubleshoot'. Also use when deployment fails."
---

# VPN Troubleshooting

Decision tree for diagnosing and fixing VPN infrastructure problems. For beginners — specific commands and solutions, not abstract methodology.

## When to Use

Use when the user reports ANY VPN problem:
- "VPN not working", "can't connect", "stopped working"
- "No internet", "slow speed", "works on Wi-Fi but not LTE"
- Deployment script failed
- Any error message related to VPN

## The Iron Law

```
DIAGNOSE BEFORE FIXING. RUN THE COMMAND BEFORE CLAIMING THE RESULT.
```

Never suggest a fix without first running diagnostics. Never claim "fixed" without verifying.

## Decision Tree

### Step 1: Can we SSH to the server?

Run: `python ssh_exec.py status`

| Result | Diagnosis | Action |
|--------|-----------|--------|
| Success (shows xray info) | SSH works | Go to Step 2 |
| "Connection refused" | Port blocked or SSH not running | Go to Branch A |
| "Authentication failed" | Wrong credentials | Go to Branch B |
| "Connection timed out" | VPS down or IP wrong | Go to Branch C |
| "No such file: .env" | Missing config | Tell user to create `.env` from `.env.example` |

#### Branch A: Connection Refused

1. Check current SSH port in `.env` (`VPN_SSH_PORT`)
2. If port is 22: TSPU often blocks port 22 to foreign IPs
   - Change `VPN_SSH_PORT=49152` in `.env`
   - Retry `python ssh_exec.py status`
3. If port is 49152 and still refused:
   - VPS firewall may block it, or SSH service is down
   - Ask user to log into VPS provider's web console and check

#### Branch B: Authentication Failed

1. Check `.env` for `VPN_SSH_KEY` and `VPN_SSH_PASS`
2. If using key: verify the key file exists at the specified path
3. If using password: ask user to verify password is correct (no extra spaces)
4. Common issue: key is for a different server (user changed VPS but kept old key)

#### Branch C: Connection Timed Out

1. Ask user: "Is your VPS running? Check in your provider's dashboard."
2. Try ping: `ping -c 3 <VPN_HOST from .env>`
3. If ping works but SSH doesn't: firewall blocks SSH port
4. If ping fails: VPS is down, IP is wrong, or ISP blocks the IP entirely

---

### Step 2: Is xray running?

From `ssh_exec.py status` output, check xray process status.

| Result | Action |
|--------|--------|
| xray: "running" | Go to Step 3 |
| xray: "stopped" or not found | Restart: `python ssh_exec.py restart` |
| After restart still not running | Check logs: `python ssh_exec.py logs` |

**Common log errors:**
- `"failed to read config"` — corrupted xray config. Re-deploy: `python ssh_exec.py deploy quick-rebuild.sh`
- `"address already in use"` — port conflict. Run: `python ssh_exec.py exec "ss -tnlp | grep -E '443|8443|2053'"`
- `"certificate not found"` — SSL cert missing. Re-deploy will regenerate it

---

### Step 3: VPN connects from client?

Ask user: "Does your VPN client (v2rayN/Shadowrocket/v2rayNG) show 'Connected'?"

| Result | Action |
|--------|--------|
| Yes, connected | Go to Step 4 |
| No, cannot connect at all | Go to Branch D |
| Connects then disconnects | Go to Branch E |

#### Branch D: Client Cannot Connect

1. **Check which port:** ask which VLESS URI the user imported (port 443, 8443, or 2053)
2. **Try another port:**
   - If using 443, try 8443 or 2053
   - Each port uses a different SNI (microsoft.com, google.com, apple.com)
3. **If NO port works:**
   - Server IP is likely blocked by TSPU
   - Solution: deploy Layer 1 relay on a Russian VPS (Timeweb/VDSina/Selectel)
   - Run: `python ssh_exec.py deploy deploy-relay-sweden.sh` (prepare main VPS)
   - Then rent a RU VPS and run: `bash deploy-relay.sh --sweden-ip ... --sweden-uuid ... --sweden-pubkey ... --sweden-sid ...`
   - NB: Yandex Cloud does NOT bypass white lists (AS Yandex.Cloud LLC != AS YANDEX LLC); use generic RU provider
   - See CLAUDE.md "Layer 1" section for full instructions
4. **Client-specific issues:**
   - v2rayN: ensure TUN mode is ON (toggle at bottom of window)
   - Shadowrocket: ensure "Global Routing" is set to "Proxy"
   - v2rayNG: ensure VPN permission is granted

#### Branch E: Connects Then Disconnects

1. Check logs: `python ssh_exec.py logs -n 50`
2. Look for repeated connection/disconnection patterns
3. Common cause: TSPU actively probing the connection
   - Try different port (8443, 2053)
   - Enable TLS fragmentation in client (100-400 bytes)

---

### Step 4: Internet works through VPN?

Ask user: "Open 2ip.ru in your browser. What country does it show?"

| Result | Action |
|--------|--------|
| Shows VPS country (Sweden/Netherlands/etc) | VPN works correctly. Go to Step 5 for optimization |
| Shows Russia | Go to Branch F |
| Page doesn't load at all | Go to Branch G |

#### Branch F: 2ip.ru Shows Russia (VPN not routing traffic)

1. **TUN mode check (critical!):**
   - v2rayN: "Enable Tun" toggle must be ON (bottom of window). Without TUN, only apps configured for proxy work, browser goes direct
   - Hiddify: DO NOT use Hiddify — switch to v2rayN (Hiddify has known QUIC/UDP leaks, see docs/05-security.md)
2. **Split routing check:**
   - 2ip.ru IS a Russian site, so with split routing enabled it SHOULD show Russia
   - Test with a non-Russian site instead: whatismyipaddress.com or ifconfig.me
   - If non-Russian sites show VPS IP: split routing works correctly
3. **Core type (v2rayN only):**
   - Settings -> Core Type -> select "sing-box" (not Xray)
   - Xray core has known issues with QUIC through SOCKS5

#### Branch G: No Internet At All

1. **DNS issue?**
   - Try accessing a site by IP directly in browser
   - If works by IP but not by domain: DNS resolution broken
   - Fix: set DNS in client to 1.1.1.1 or 8.8.8.8
2. **Routing issue?**
   - Disable split routing temporarily (use "Global" mode)
   - If Global mode works: split routing config has errors
3. **Server-side DNS:**
   - Run: `python ssh_exec.py exec "nslookup google.com"`
   - If fails: `python ssh_exec.py exec "systemctl restart systemd-resolved"`

---

### Step 5: Performance Issues

| Symptom | Diagnostic | Fix |
|---------|-----------|-----|
| Slow overall | `python ssh_exec.py exec "sysctl net.ipv4.tcp_congestion_control"` | Should be "bbr". If not: `python ssh_exec.py deploy quick-rebuild.sh` will enable it |
| Slow on LTE | Mobile operator throttling | Enable TLS fragmentation (100-400 bytes) in client settings |
| YouTube buffers | Check core type in v2rayN | Switch to sing-box core. QUIC/UDP may be broken with Xray core |
| Slow on Wi-Fi, fast on LTE | Unusual, likely ISP issue | Try Cloudflare DNS (1.1.1.1) in router settings |

---

### Step 6: Works on Wi-Fi, Not on LTE

This is a **specific and common problem** caused by mobile operators using "white lists" (only allowing traffic to known Russian IPs).

**Solution: Deploy Layer 1 (Relay on Russian VPS)**

IP ranges of Russian VPS providers (Timeweb, VDSina, Selectel) may be in the white list of mobile operators — but this is NOT guaranteed. You must verify after deploy.

> **NB:** Yandex Cloud was previously recommended here; removed 2026-04-17 after Habr 1021160 comments (@paxlo/@aax/@Varpun) proved AS Yandex.Cloud LLC (user VMs) != AS YANDEX LLC (Yandex services) — TSPU filters them separately, YC VMs get blocked under active white lists.

1. Prepare main VPS: `python ssh_exec.py deploy deploy-relay-sweden.sh`
2. Fill relay credentials in `.env` (`SWEDEN_RELAY_UUID`, `SWEDEN_RELAY_PUBKEY`, `SWEDEN_RELAY_SID`)
3. Rent a Russian VPS (Timeweb Cloud ~80 RUB/mo, VDSina ~100 RUB/mo), fill `RELAY_HOST` in `.env`
4. Deploy relay: `bash deploy-relay.sh --sweden-ip $SWEDEN_VPS_IP --sweden-uuid $SWEDEN_RELAY_UUID --sweden-pubkey $SWEDEN_RELAY_PUBKEY --sweden-sid $SWEDEN_RELAY_SID`
5. Import the relay VLESS URI into client
6. Test on LTE — if blocked, try a different Russian provider

See CLAUDE.md "Layer 1" section for details.

---

## Relay VPS Troubleshooting

If user has Layer 1 (relay) deployed and it stops working:

1. `python ssh_exec.py -t relay status` — check relay xray
2. `python ssh_exec.py -t relay logs` — check relay logs
3. `python ssh_exec.py -t relay restart` — restart relay
4. `bash monitor-relay.sh` — health check both VPSes
5. Verify main VPS accepts relay connections: `python ssh_exec.py exec "ss -tnp | grep 10443"`

## Communication Rules

- Communicate in **Russian**
- Run diagnostic commands BEFORE suggesting fixes
- Show the user what each command found (summarize, don't dump raw output)
- If a fix doesn't work, go back to diagnostics, don't keep guessing
- For complex issues, reference `docs/08-operations.md` for additional guidance
