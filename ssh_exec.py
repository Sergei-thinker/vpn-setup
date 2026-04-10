#!/usr/bin/env python3
"""
SSH management tool for VPN server(s).

Supports SSH key authentication (preferred) with password fallback.
Configuration via environment variables or .env file.
Supports dual-VPS management: Swedish (default) and Russian relay.

Usage:
    python ssh_exec.py status                    # Swedish VPS (default)
    python ssh_exec.py -t relay status           # Russian relay VPS
    python ssh_exec.py -t relay logs             # Relay Xray logs
    python ssh_exec.py -t relay restart          # Restart relay
    python ssh_exec.py relay-status              # Both VPSes combined
    python ssh_exec.py exec "command"            # Execute on Swedish VPS
    python ssh_exec.py deploy <script.sh>        # Deploy to Swedish VPS
    python ssh_exec.py backup                    # Download x-ui database
    python ssh_exec.py update-xray               # Update xray-core
"""

import argparse
import os
import sys
import datetime
from pathlib import Path

import paramiko
import scp as scp_module  # pip install scp


# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------

class Color:
    """ANSI color codes (disabled automatically when stdout is not a TTY)."""
    _enabled = sys.stdout.isatty()

    RESET  = "\033[0m"  if _enabled else ""
    BOLD   = "\033[1m"  if _enabled else ""
    RED    = "\033[91m" if _enabled else ""
    GREEN  = "\033[92m" if _enabled else ""
    YELLOW = "\033[93m" if _enabled else ""
    CYAN   = "\033[96m" if _enabled else ""
    DIM    = "\033[2m"  if _enabled else ""


def info(msg: str) -> None:
    print(f"{Color.CYAN}[INFO]{Color.RESET} {msg}")


def ok(msg: str) -> None:
    print(f"{Color.GREEN}[OK]{Color.RESET} {msg}")


def warn(msg: str) -> None:
    print(f"{Color.YELLOW}[WARN]{Color.RESET} {msg}")


def error(msg: str) -> None:
    print(f"{Color.RED}[ERROR]{Color.RESET} {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# .env loader (no external dependency required)
# ---------------------------------------------------------------------------

def load_dotenv(path: str | Path | None = None) -> None:
    """Load key=value pairs from a .env file into os.environ."""
    if path is None:
        path = Path(__file__).resolve().parent / ".env"
    else:
        path = Path(path)

    if not path.is_file():
        return

    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("'\"")
            os.environ.setdefault(key, value)


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

def get_config(target: str = "sweden") -> dict:
    """Build SSH config from environment (with sane defaults).

    Args:
        target: 'sweden' for main VPS, 'relay' for Russian relay VPS.
    """
    load_dotenv()

    home = Path.home()
    default_key = str(home / ".ssh" / "id_ed25519")

    if target == "relay":
        return {
            "host":     os.environ.get("RELAY_HOST", ""),
            "port":     int(os.environ.get("RELAY_SSH_PORT", "22")),
            "user":     os.environ.get("RELAY_SSH_USER", "root"),
            "key_path": os.environ.get("RELAY_SSH_KEY", default_key),
            "password": os.environ.get("RELAY_SSH_PASS"),
            "target":   "relay",
            "provider": os.environ.get("RELAY_PROVIDER", "generic"),
        }

    return {
        "host":     os.environ.get("VPN_HOST", ""),
        "port":     int(os.environ.get("VPN_SSH_PORT", "49152")),
        "user":     os.environ.get("VPN_SSH_USER", "root"),
        "key_path": os.environ.get("VPN_SSH_KEY", default_key),
        "password": os.environ.get("VPN_SSH_PASS"),
        "target":   "sweden",
    }


# ---------------------------------------------------------------------------
# SSH connection
# ---------------------------------------------------------------------------

def connect(cfg: dict) -> paramiko.SSHClient:
    """Open an SSH connection using key auth (preferred) or password fallback."""
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    key_path = Path(cfg["key_path"]).expanduser()
    # Also try common key locations
    key_candidates = [
        key_path,
        Path.home() / ".ssh" / "id_ed25519",
        Path.home() / ".ssh" / "id_rsa",
    ]
    # Deduplicate while preserving order
    seen = set()
    unique_keys = []
    for k in key_candidates:
        resolved = k.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique_keys.append(k)

    # Try key-based authentication first
    for kp in unique_keys:
        if kp.is_file():
            try:
                info(f"Trying SSH key: {kp}")
                client.connect(
                    cfg["host"],
                    port=cfg["port"],
                    username=cfg["user"],
                    key_filename=str(kp),
                    timeout=15,
                )
                ok(f"Connected via SSH key: {kp}")
                return client
            except paramiko.AuthenticationException:
                warn(f"Key rejected: {kp}")
            except Exception as exc:
                warn(f"Key error ({kp}): {exc}")

    # Fallback to password
    password = cfg.get("password")
    if password:
        try:
            info("Trying password authentication...")
            client.connect(
                cfg["host"],
                port=cfg["port"],
                username=cfg["user"],
                password=password,
                timeout=15,
            )
            ok("Connected via password.")
            return client
        except paramiko.AuthenticationException:
            error("Password authentication failed.")
        except Exception as exc:
            error(f"Connection error: {exc}")

    error(
        "All authentication methods failed.\n"
        "  - Place an SSH key at ~/.ssh/id_ed25519 (or set VPN_SSH_KEY)\n"
        "  - Or set VPN_SSH_PASS environment variable"
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Command execution helpers
# ---------------------------------------------------------------------------

def run_commands(client: paramiko.SSHClient, commands: list[str], *, quiet: bool = False) -> str:
    """Execute a list of commands, print output, return last stdout."""
    last_out = ""
    for cmd in commands:
        if not quiet:
            sys.stdout.buffer.write(f"\n{Color.BOLD}{Color.DIM}>>> {cmd}{Color.RESET}\n".encode("utf-8", errors="replace"))
            sys.stdout.buffer.flush()
        stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
        out = stdout.read().decode("utf-8", errors="replace").strip()
        err = stderr.read().decode("utf-8", errors="replace").strip()
        if out:
            sys.stdout.buffer.write((out + "\n").encode("utf-8", errors="replace"))
            sys.stdout.buffer.flush()
        if err and not quiet:
            sys.stdout.buffer.write(f"{Color.YELLOW}{err}{Color.RESET}\n".encode("utf-8", errors="replace"))
            sys.stdout.buffer.flush()
        last_out = out
    return last_out


def upload_file(client: paramiko.SSHClient, local_path: str, remote_path: str) -> None:
    """Upload a local file to the remote server via SCP."""
    with scp_module.SCPClient(client.get_transport()) as scp_client:
        scp_client.put(local_path, remote_path)
    ok(f"Uploaded {local_path} -> {remote_path}")


def download_file(client: paramiko.SSHClient, remote_path: str, local_path: str) -> None:
    """Download a file from the remote server via SCP."""
    with scp_module.SCPClient(client.get_transport()) as scp_client:
        scp_client.get(remote_path, local_path)
    ok(f"Downloaded {remote_path} -> {local_path}")


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_exec(args, cfg):
    """Execute an arbitrary command on the server."""
    client = connect(cfg)
    try:
        run_commands(client, [args.command])
    finally:
        client.close()


def cmd_status(args, cfg):
    """Show xray/x-ui status, uptime, and active connections."""
    is_relay = cfg.get("target") == "relay"
    label = "Relay VPS" if is_relay else "Swedish VPS"

    client = connect(cfg)
    try:
        commands = ["uptime"]
        if is_relay:
            # Relay has standalone xray, no x-ui
            commands += [
                "systemctl is-active xray && echo 'xray: running' || echo 'xray: stopped'",
                "ss -tnp | grep -c xray || echo '0 xray connections'",
            ]
        else:
            commands += [
                "systemctl is-active x-ui && echo 'x-ui: running' || echo 'x-ui: stopped'",
                "systemctl is-active xray 2>/dev/null && echo 'xray: running' || echo 'xray: managed by x-ui or not found'",
                "ss -tnp | grep -c xray || echo '0 xray connections'",
            ]
        commands += [
            "free -h | head -2",
            "df -h / | tail -1",
        ]
        print(f"\n{Color.BOLD}=== {label} Status ==={Color.RESET}")
        run_commands(client, commands)
    finally:
        client.close()


def cmd_relay_status(args, cfg):
    """Show combined status of both VPSes (Sweden + Relay)."""
    for target_name in ("sweden", "relay"):
        target_cfg = get_config(target_name)
        label = "Swedish VPS (Layer 0/1)" if target_name == "sweden" else "Russian Relay (Layer 2)"

        if not target_cfg.get("host"):
            print(f"\n{Color.YELLOW}=== {label}: not configured (RELAY_HOST empty) ==={Color.RESET}")
            continue

        print(f"\n{Color.BOLD}=== {label} [{target_cfg['host']}] ==={Color.RESET}")
        try:
            client = connect(target_cfg)
            try:
                is_relay = target_name == "relay"
                commands = ["uptime"]
                if is_relay:
                    commands += [
                        "systemctl is-active xray && echo 'xray: running' || echo 'xray: stopped'",
                        "ss -tnp | grep -c xray || echo '0 xray connections'",
                    ]
                else:
                    commands += [
                        "systemctl is-active x-ui && echo 'x-ui: running' || echo 'x-ui: stopped'",
                        "systemctl is-active xray 2>/dev/null && echo 'xray: running' || echo 'xray: managed by x-ui'",
                        "ss -tnp | grep -c xray || echo '0 xray connections'",
                    ]
                run_commands(client, commands)
            finally:
                client.close()
        except Exception as exc:
            error(f"{label}: connection failed — {exc}")


def cmd_restart(args, cfg):
    """Restart x-ui and xray services."""
    is_relay = cfg.get("target") == "relay"
    service = "xray" if is_relay else "x-ui"

    client = connect(cfg)
    try:
        print(f"\n{Color.BOLD}=== Restarting {service} ==={Color.RESET}")
        run_commands(client, [
            f"systemctl restart {service}",
            "sleep 2",
            f"systemctl is-active {service} && echo '{service} restarted successfully' || echo '{service} FAILED to restart'",
        ])
    finally:
        client.close()


def cmd_logs(args, cfg):
    """Show recent xray / x-ui logs."""
    is_relay = cfg.get("target") == "relay"
    service = "xray" if is_relay else "x-ui"
    lines = getattr(args, "lines", 50)

    client = connect(cfg)
    try:
        print(f"\n{Color.BOLD}=== Recent {service} logs (last {lines} lines) ==={Color.RESET}")
        run_commands(client, [
            f"journalctl -u {service} --no-pager -n {lines}",
        ])
    finally:
        client.close()


def cmd_deploy(args, cfg):
    """Upload a local script and execute it on the server."""
    script = args.script
    if not os.path.isfile(script):
        error(f"File not found: {script}")
        sys.exit(1)

    remote_path = f"/tmp/{os.path.basename(script)}"
    client = connect(cfg)
    try:
        upload_file(client, script, remote_path)
        run_commands(client, [
            f"chmod +x {remote_path}",
            f"bash {remote_path}",
        ])
        info(f"Script executed. Remote copy at {remote_path}")
    finally:
        client.close()


def cmd_backup(args, cfg):
    """Download the x-ui database backup."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    local_dir = Path(__file__).resolve().parent / "backups"
    local_dir.mkdir(exist_ok=True)
    local_file = local_dir / f"x-ui-{timestamp}.db"

    # Common x-ui database paths
    db_paths = [
        "/etc/x-ui/x-ui.db",
        "/usr/local/x-ui/x-ui.db",
    ]

    client = connect(cfg)
    try:
        for db_path in db_paths:
            check = run_commands(client, [f"test -f {db_path} && echo EXISTS || echo MISSING"], quiet=True)
            if "EXISTS" in check:
                download_file(client, db_path, str(local_file))
                ok(f"Backup saved to {local_file}")
                return

        error("x-ui database not found at known paths. Searching...")
        run_commands(client, ["find / -name 'x-ui.db' 2>/dev/null | head -5"])
    finally:
        client.close()


def cmd_update_xray(args, cfg):
    """Update xray-core to the latest version."""
    client = connect(cfg)
    try:
        print(f"\n{Color.BOLD}=== Updating xray-core ==={Color.RESET}")
        run_commands(client, [
            "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) --update",
        ])
        ok("Update command executed. Check output above for results.")
    finally:
        client.close()


def cmd_yc_status(args, cfg):
    """Show Yandex Cloud relay VM status via yc CLI (no SSH required)."""
    import subprocess
    import json

    load_dotenv()
    folder_id = os.environ.get("YC_FOLDER_ID", "")
    vm_name = os.environ.get("YC_VM_NAME", "vpn-relay")

    if not folder_id:
        # Try yc config
        try:
            result = subprocess.run(["yc", "config", "get", "folder-id"],
                                    capture_output=True, text=True, timeout=10)
            folder_id = result.stdout.strip()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    if not folder_id:
        error("YC_FOLDER_ID not set and yc config unavailable")
        sys.exit(1)

    print(f"\n{Color.BOLD}=== Yandex Cloud Relay VM ==={Color.RESET}")

    try:
        result = subprocess.run(
            ["yc", "compute", "instance", "get",
             "--name", vm_name, "--folder-id", folder_id, "--format", "json"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            error(f"VM '{vm_name}' not found: {result.stderr.strip()}")
            sys.exit(1)

        vm = json.loads(result.stdout)
        status = vm.get("status", "UNKNOWN")
        created = vm.get("created_at", "?")
        zone = vm.get("zone_id", "?")

        # Extract IP
        ip = ""
        ifaces = vm.get("network_interfaces", [])
        if ifaces:
            nat = ifaces[0].get("primary_v4_address", {}).get("one_to_one_nat", {})
            ip = nat.get("address", "")

        # Color status
        status_color = Color.GREEN if status == "RUNNING" else Color.RED if status == "STOPPED" else Color.YELLOW

        print(f"  VM Name:   {vm_name}")
        print(f"  Status:    {status_color}{status}{Color.RESET}")
        print(f"  IP:        {ip or 'N/A'}")
        print(f"  Zone:      {zone}")
        print(f"  Created:   {created}")

        preemptible = vm.get("scheduling_policy", {}).get("preemptible", False)
        if preemptible:
            print(f"  {Color.YELLOW}Preemptible: VM will be stopped after 24h{Color.RESET}")

        # Check if RELAY_HOST matches
        current_relay = os.environ.get("RELAY_HOST", "")
        if ip and current_relay and ip != current_relay:
            warn(f"IP mismatch! VM: {ip}, .env RELAY_HOST: {current_relay}")
            warn("Run rotate-relay-yc.sh to update")

    except FileNotFoundError:
        error("yc CLI not found. Install: curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        error("yc CLI timed out")
        sys.exit(1)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="SSH management tool for VPN server(s)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Configuration (env vars or .env file):\n"
            "  Swedish VPS:   VPN_HOST, VPN_SSH_PORT, VPN_SSH_USER, VPN_SSH_KEY, VPN_SSH_PASS\n"
            "  Relay VPS:     RELAY_HOST, RELAY_SSH_PORT, RELAY_SSH_USER, RELAY_SSH_KEY, RELAY_SSH_PASS\n"
        ),
    )
    parser.add_argument(
        "--target", "-t",
        choices=["sweden", "relay"],
        default="sweden",
        help="Target VPS: sweden (default) or relay",
    )
    sub = parser.add_subparsers(dest="command_name", help="Available commands")

    # exec
    p_exec = sub.add_parser("exec", help="Execute an arbitrary command")
    p_exec.add_argument("command", help="Command to execute on the server")
    p_exec.set_defaults(func=cmd_exec)

    # status
    p_status = sub.add_parser("status", help="Show server/xray status")
    p_status.set_defaults(func=cmd_status)

    # restart
    p_restart = sub.add_parser("restart", help="Restart x-ui / xray")
    p_restart.set_defaults(func=cmd_restart)

    # logs
    p_logs = sub.add_parser("logs", help="Show recent xray logs")
    p_logs.add_argument("-n", "--lines", type=int, default=50, help="Number of log lines (default: 50)")
    p_logs.set_defaults(func=cmd_logs)

    # deploy
    p_deploy = sub.add_parser("deploy", help="Upload and execute a script")
    p_deploy.add_argument("script", help="Path to local script file")
    p_deploy.set_defaults(func=cmd_deploy)

    # backup
    p_backup = sub.add_parser("backup", help="Download x-ui database backup")
    p_backup.set_defaults(func=cmd_backup)

    # update-xray
    p_update = sub.add_parser("update-xray", help="Update xray-core to latest")
    p_update.set_defaults(func=cmd_update_xray)

    # relay-status (combined view of both VPSes)
    p_relay_status = sub.add_parser("relay-status", help="Show status of both VPSes (Sweden + Relay)")
    p_relay_status.set_defaults(func=cmd_relay_status)

    # yc-status (Yandex Cloud VM status via yc CLI)
    p_yc_status = sub.add_parser("yc-status", help="Show Yandex Cloud relay VM status (no SSH)")
    p_yc_status.set_defaults(func=cmd_yc_status)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if not args.command_name:
        parser.print_help()
        sys.exit(0)

    cfg = get_config(args.target)

    # Commands that handle their own connections (no SSH needed)
    if args.command_name in ("relay-status", "yc-status"):
        try:
            args.func(args, cfg)
        except KeyboardInterrupt:
            warn("\nInterrupted.")
            sys.exit(130)
        return

    if not cfg.get("host"):
        error(f"Target '{args.target}' not configured. Set RELAY_HOST in .env")
        sys.exit(1)

    info(f"Target: {cfg['user']}@{cfg['host']}:{cfg['port']} ({args.target})")

    try:
        args.func(args, cfg)
    except KeyboardInterrupt:
        warn("\nInterrupted.")
        sys.exit(130)
    except paramiko.SSHException as exc:
        error(f"SSH error: {exc}")
        sys.exit(1)
    except Exception as exc:
        error(f"Unexpected error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
