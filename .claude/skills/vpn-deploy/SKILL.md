---
name: vpn-deploy
description: "Guided VPN deployment wizard. Use when user says 'deploy VPN', 'deploy my VPN', 'set up VPN', 'install VPN'. Also use when opening the project for the first time and user wants to get started."
---

# VPN Deployment Wizard

Управляемый деплой VPN-инфраструктуры для начинающих пользователей. Каждый шаг проверяется перед переходом к следующему.

## When to Use

Use when the user wants to deploy a VPN:
- "Deploy VPN", "deploy my VPN"
- "Set up VPN", "install VPN"
- "Help me get started"

## The Iron Law

```
NO STEP WITHOUT VERIFICATION OF THE PREVIOUS STEP
```

Do not proceed to deployment if connectivity check failed. Do not claim success without running status check.

## Workflow

Execute these phases IN ORDER. Do not skip phases.

### Phase 1: Environment Setup

**Goal:** Ensure `.env` file exists and is correctly filled.

1. Check if `.env` file exists in project root
2. If NO:
   - Read `.env.example` to understand required fields
   - Ask user for VPS details (in Russian):
     - IP-адрес VPS (`VPN_HOST`)
     - SSH-порт (default 22, recommend 49152)
     - SSH-пользователь (default root)
     - SSH-ключ path OR пароль (`VPN_SSH_KEY` or `VPN_SSH_PASS`)
   - Create `.env` from `.env.example` with user's values
3. If YES:
   - Read `.env` and verify `VPN_HOST` is set (not placeholder `<YOUR_VPS_IP>`)
   - If placeholder values remain, ask user to fill them

**Verification:** `.env` exists AND `VPN_HOST` contains a real IP address.

### Phase 2: Dependency Check

**Goal:** Ensure Python 3 and paramiko are available.

1. Run `python --version` or `python3 --version`
2. If Python not found: tell user to install Python 3
3. Run `python -c "import paramiko; print(paramiko.__version__)"`
4. If paramiko not found: run `pip install paramiko scp`

**Verification:** Both Python 3 and paramiko import successfully.

### Phase 3: Connectivity Test

**Goal:** Verify SSH access to VPS.

1. Run `python ssh_exec.py status`
2. Interpret output:
   - **Success:** xray status shown, uptime visible -> proceed
   - **"Connection refused":** Port might be blocked. If port is 22, suggest trying 49152 (TSPU blocks port 22 to foreign IPs). Update `.env` and retry
   - **"Authentication failed":** Wrong password or SSH key. Ask user to verify credentials
   - **"Connection timed out":** VPS might be down or IP wrong. Ask user to verify VPS is running
   - **"Host key verification failed":** First connection to this server. Ask user to confirm the IP is correct, then suggest removing old known_hosts entry if IP was reused

**Verification:** `ssh_exec.py status` returns xray status or server info without errors.

**Special case — fresh VPS (xray not installed yet):** If SSH connects but xray is not found, that's EXPECTED for first-time deployment. Proceed to Phase 4.

### Phase 4: Deployment

**Goal:** Deploy VPN infrastructure on the VPS.

1. Inform user: "Starting deployment. This takes 15-20 minutes. The script will install 3X-UI panel, create VLESS Reality connections, configure firewall and monitoring."
2. Run `python ssh_exec.py deploy quick-rebuild.sh`
3. Monitor output for:
   - **VLESS URIs** (lines starting with `vless://`) — SAVE ALL OF THEM
   - **Error messages** — if script fails, check the last error message
   - **Credentials** (panel URL, username, password) — note these for user
4. If deployment fails:
   - Read error output
   - Common issues: disk space, network timeout during package install, port conflict
   - Suggest: `python ssh_exec.py restart` then retry deployment

**Verification:** Script completes without errors AND outputs at least one VLESS URI.

### Phase 5: Post-Deploy Verification

**Goal:** Confirm VPN is actually running.

1. Run `python ssh_exec.py status`
2. Verify:
   - xray process is "running"
   - At least one inbound is active
   - Server uptime is fresh (just deployed)
3. If xray is not running: `python ssh_exec.py restart`, then check again

**Verification:** `ssh_exec.py status` shows xray running with active inbounds.

### Phase 6: Client Setup Instructions

**Goal:** Give user everything needed to connect.

Based on user's platform, provide:

**Windows (v2rayN — recommended):**
1. Present all VLESS URIs from deployment output
2. Point to `client-configs/v2rayn-setup.md` for detailed setup
3. Key points:
   - Import URI via clipboard
   - Enable TUN mode (critical — without it, DNS and UDP leak)
   - Select split routing preset "RUv1" (Russian sites bypass VPN)
   - Use sing-box core for best compatibility

**iOS (Shadowrocket — recommended):**
1. Present VLESS URIs
2. Point to `docs/04-client-setup.md` iOS section
3. Key: copy URI -> open Shadowrocket -> auto-imports

**Android (v2rayNG):**
1. Present VLESS URIs
2. Point to `docs/04-client-setup.md` Android section

**Verification (user does this manually):**
- Tell user: "After connecting, open 2ip.ru in your browser. It should show your VPS country (Sweden/Netherlands/etc), NOT Russia. For Russian sites (yandex.ru, vk.com), it should show Russia."

## Communication Rules

- Communicate with user in **Russian** (per CLAUDE.md)
- Never display raw credentials or `.env` contents in chat output
- Present VLESS URIs clearly — user needs to copy them
- If something fails, explain in simple terms what happened and what to try next
- Do not overwhelm beginner with technical details — keep explanations concise
