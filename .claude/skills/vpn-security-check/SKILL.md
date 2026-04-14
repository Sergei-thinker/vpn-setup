---
name: vpn-security-check
description: "Infrastructure security audit for VPN server. Use when user asks 'check security', 'is my VPN safe', 'audit security', 'security check'. Also use after deployment when user has security concerns."
---

# VPN Infrastructure Security Audit

Checks that the VPN server is properly hardened. All checks run via `ssh_exec.py` — no additional tools needed.

## When to Use

- User asks about security: "check security", "is my VPN safe"
- After initial deployment (offer proactively)
- User has security concerns
- Periodic security checkup

## The Iron Law

```
EVERY CHECK MUST RUN A COMMAND. NO ASSUMPTIONS.
```

"quick-rebuild.sh enables the firewall" is not evidence that the firewall is active. Run the check.

## Security Checks

Run ALL checks in order. Report each as PASS/FAIL/WARN with evidence.

### 1. SSH Hardening

**1a. SSH Port**

Command: `python ssh_exec.py exec "grep -E '^Port ' /etc/ssh/sshd_config"`

| Result | Rating |
|--------|--------|
| Port != 22 (e.g., 49152) | PASS |
| Port 22 | FAIL — TSPU scans and blocks port 22 to foreign IPs. Change with: `python ssh_exec.py exec "sed -i 's/^Port 22/Port 49152/' /etc/ssh/sshd_config && systemctl restart sshd"` |

**1b. Root Password Login**

Command: `python ssh_exec.py exec "grep -E '^PasswordAuthentication' /etc/ssh/sshd_config"`

| Result | Rating |
|--------|--------|
| PasswordAuthentication no | PASS |
| PasswordAuthentication yes | WARN — Key-only auth is more secure. Note: some beginners use password auth intentionally. Inform, don't force change |
| Not set (commented out) | WARN — defaults to yes on most distros |

### 2. Firewall

**2a. UFW Status**

Command: `python ssh_exec.py exec "ufw status verbose"`

| Result | Rating |
|--------|--------|
| Status: active, rules for 443/8443/2053/SSH port | PASS |
| Status: inactive | FAIL — `python ssh_exec.py exec "ufw --force enable"` |
| Active but missing expected ports | WARN — check if needed ports are open |

**2b. Open Ports (reality check)**

Command: `python ssh_exec.py exec "ss -tnlp | grep -E 'LISTEN' | awk '{print \$4, \$6}'"`

Verify only expected services are listening:
- xray on 443, 8443, 2053 (VPN)
- x-ui panel (some high port)
- sshd on configured port
- nginx on 80 (camouflage)

Any unexpected service = WARN

### 3. Intrusion Prevention

**3a. fail2ban**

Command: `python ssh_exec.py exec "systemctl is-active fail2ban && fail2ban-client status sshd 2>/dev/null | grep -E 'Currently|Total'"`

| Result | Rating |
|--------|--------|
| active + shows ban stats | PASS |
| inactive or not installed | FAIL — `python ssh_exec.py exec "apt install -y fail2ban && systemctl enable --now fail2ban"` |

### 4. VPN Service Security

**4a. 3X-UI Panel Access**

Command: `python ssh_exec.py exec "grep -E 'webPort|webBasePath' /etc/x-ui/x-ui.db 2>/dev/null || echo 'db not readable as text'"`

Check:
- Panel is on non-standard port (not 80, 443, 8080, 2053)
- Panel base path is randomized (not `/` or `/panel`)

If DB not readable as text, try: `python ssh_exec.py exec "x-ui settings show 2>/dev/null || echo 'cannot read settings'"`

| Result | Rating |
|--------|--------|
| Non-standard port + randomized path | PASS |
| Default port or path = "/" | WARN — Panel is discoverable. Suggest changing via `x-ui settings` |

**4b. Xray Running with Expected Config**

Command: `python ssh_exec.py exec "xray version 2>/dev/null || /usr/local/x-ui/bin/xray-linux-amd64 version 2>/dev/null"`

| Result | Rating |
|--------|--------|
| Version >= 24.x | PASS |
| Old version | WARN — Update with `python ssh_exec.py update-xray` |

### 5. Camouflage

**5a. Nginx Responding**

Command: `python ssh_exec.py exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:80"`

| Result | Rating |
|--------|--------|
| 200 | PASS — Camouflage page is active |
| Connection refused / other | WARN — Without nginx, port scanners see an unusual server profile |

### 6. Secrets Management

**6a. .env Not in Git**

Command (local): Check `.gitignore` includes `.env` AND `git ls-files .env` returns nothing

| Result | Rating |
|--------|--------|
| .env is gitignored and not tracked | PASS |
| .env is tracked in git | CRITICAL FAIL — `git rm --cached .env` immediately. Credentials are exposed! |

**6b. Credentials File Permissions (on server)**

Command: `python ssh_exec.py exec "ls -la /root/vpn-credentials.txt 2>/dev/null || echo 'not found'"`

| Result | Rating |
|--------|--------|
| Permissions -rw------- (600) or not found | PASS |
| World-readable (644, 755, etc.) | WARN — `python ssh_exec.py exec "chmod 600 /root/vpn-credentials.txt"` |

### 7. System Updates

Command: `python ssh_exec.py exec "apt list --upgradable 2>/dev/null | tail -n +2 | wc -l"`

| Result | Rating |
|--------|--------|
| 0 or <5 pending updates | PASS |
| 5+ pending security updates | WARN — `python ssh_exec.py exec "apt update && apt upgrade -y"` |

## Report Format

Present as a security scorecard (in Russian):

```
Аудит безопасности VPN-сервера:

  SSH:
    1a. SSH-порт:              [PASS/FAIL]
    1b. Парольная авторизация: [PASS/WARN]
  
  Firewall:
    2a. UFW:                   [PASS/FAIL]
    2b. Открытые порты:        [PASS/WARN]
  
  Защита от вторжений:
    3a. fail2ban:              [PASS/FAIL]
  
  VPN-сервис:
    4a. Панель 3X-UI:          [PASS/WARN]
    4b. Версия Xray:           [PASS/WARN]
  
  Камуфляж:
    5a. Nginx:                 [PASS/WARN]
  
  Секреты:
    6a. .env в git:            [PASS/CRITICAL]
    6b. Файл credentials:     [PASS/WARN]
  
  Обновления:
    7.  Системные:             [PASS/WARN]

Итого: X/10 проверок пройдено
```

For each FAIL/WARN: provide the specific fix command.
For CRITICAL: fix immediately before continuing.

## Communication Rules

- Communicate in **Russian**
- Run every check — do not skip "because the deploy script handles it"
- If a check fails, provide the exact fix command
- Do not alarm the user unnecessarily — WARN is informational, FAIL needs action, CRITICAL needs immediate action
- Remind user this is an infrastructure audit, not a guarantee of anonymity (VPN protects from censorship, not from targeted surveillance)
