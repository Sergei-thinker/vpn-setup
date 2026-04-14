---
name: vpn-verify
description: "Post-deployment verification checklist for VPN. Use AUTOMATICALLY after any deployment action (deploy, rebuild, restart) and BEFORE claiming deployment is complete or successful. Evidence before assertions."
---

# VPN Deployment Verification

Mandatory verification checklist after ANY deployment or change to VPN infrastructure. No completion claims without fresh evidence.

## When to Use

**AUTOMATICALLY** (do not wait for user to ask):
- After running `ssh_exec.py deploy quick-rebuild.sh`
- After running any `deploy-*.sh` script
- After `ssh_exec.py restart`
- Before saying "done", "deployed", "VPN is ready", or any success claim

**On request:**
- User asks "is it working?", "did it deploy correctly?"
- User asks to verify/check the VPN

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run `ssh_exec.py status` in THIS message, you cannot claim deployment succeeded.

"Should be working" is not verification. Run the command.

## Verification Checklist

Execute ALL checks. Report results as pass/fail with evidence.

### Check 1: Xray Process Running

**Command:** `python ssh_exec.py status`

| Output | Result |
|--------|--------|
| Shows "xray" with "running" status | PASS |
| Shows "stopped", "failed", or no xray info | FAIL -> `python ssh_exec.py restart`, then re-check |
| SSH connection error | FAIL -> run vpn-troubleshoot |

### Check 2: VLESS URIs Generated

**What to verify:** Deployment script output contained at least one line starting with `vless://`

| Condition | Result |
|-----------|--------|
| 1+ VLESS URIs captured from deploy output | PASS |
| No URIs in output | FAIL -> check deploy logs, may need to re-run |

### Check 3: Server IP Matches Config

**What to verify:** The IP address in the VLESS URI matches `VPN_HOST` in `.env`

**How:** Read `.env`, extract `VPN_HOST`, compare with the IP in captured VLESS URIs.

| Condition | Result |
|-----------|--------|
| IPs match | PASS |
| IPs differ | FAIL -> `.env` may be outdated or URI is from old deployment |

### Check 4: SSH Port Changed

**Command:** Check `VPN_SSH_PORT` in `.env` OR run `python ssh_exec.py exec "grep -E '^Port ' /etc/ssh/sshd_config"`

| Condition | Result |
|-----------|--------|
| SSH port is NOT 22 (typically 49152) | PASS |
| SSH port is still 22 | WARN -> "TSPU can block port 22 to foreign IPs. Consider changing." |

### Check 5: Firewall Active

**Command:** `python ssh_exec.py exec "ufw status | head -1"`

| Output | Result |
|--------|--------|
| "Status: active" | PASS |
| "Status: inactive" or command not found | FAIL -> `python ssh_exec.py exec "ufw --force enable"` |

### Check 6: Inbound Ports Listening

**Command:** `python ssh_exec.py exec "ss -tnlp | grep xray"`

| Output | Result |
|--------|--------|
| Shows ports 443, 8443, 2053 (at least one) | PASS |
| No xray ports listening | FAIL -> restart xray, check config |

## Report Format

After all checks, present a summary:

```
Результаты проверки деплоя:
  1. Xray процесс:     [PASS/FAIL]
  2. VLESS URI:         [PASS/FAIL]
  3. IP совпадает:      [PASS/FAIL]
  4. SSH порт:          [PASS/WARN]
  5. Firewall:          [PASS/FAIL]
  6. Порты слушают:     [PASS/FAIL]
```

If ALL pass: provide user with VLESS URIs and client setup instructions.
If ANY fail: diagnose the failure, do NOT claim success.

## Red Flags — STOP Immediately

You are about to violate this rule if you catch yourself:
- Writing "deployed successfully" without running `ssh_exec.py status` first
- Saying "VPN is ready" based on script exit code alone
- Assuming firewall is active because the script enables it
- Presenting URIs without verifying xray is actually running
- Using words like "should work", "probably deployed", "looks good"

## After Verification Passes

Tell user (in Russian):
1. Present the VLESS URIs clearly
2. Remind: "Import URI into your VPN client"
3. Remind: "Enable TUN mode" (critical)
4. Remind: "Test by opening 2ip.ru — should show VPS country for non-Russian sites"
5. Point to platform-specific setup guide (`client-configs/v2rayn-setup.md` for Windows)
