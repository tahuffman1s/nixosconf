#!/usr/bin/env python3
"""NixOS Updater: update this machine from its flake and keep the parts of the
config that describe this machine (Flatpaks, autostart, shortcuts, systemd
units, scripts, unattended updates) in sync, committing every change.

GUI by default (Qt, follows the Plasma style). Subcommands for the terminal:

    nixos-updater update [--no-sync]   sync, refresh inputs, rebuild, update flatpaks
    nixos-updater sync [--dry-run]     import flatpaks and autostart entries into the config
    nixos-updater apply                rebuild from the config as it is now
    nixos-updater flush                remove old generations and unused flatpaks
    nixos-updater push                 git push the config repo
    nixos-updater reboot
    nixos-updater unit add FILE [--user] [--disabled] | remove NAME | list
    nixos-updater script add FILE... [--data] [--post-update] | remove NAME | run NAME | list
    nixos-updater script post-update NAME on|off
"""

import argparse
import configparser
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

APP_NAME = "NixOS Updater"
APP_ID = "nixos-updater"
FLAKE_HOST = "nixos"
CONFIG_LINK = os.environ.get("NIXOS_UPDATER_CONFIG", "/etc/nixos")
CONFIG_DIR = Path(os.path.realpath(CONFIG_LINK))
HELPER = Path(__file__).resolve().parent.parent / "libexec" / "nixos-updater-helper"

FILES = {
    "flatpaks": CONFIG_DIR / "Apps" / "flatpaks.json",
    "autostart": CONFIG_DIR / "Home" / "autostart.json",
    "shortcuts": CONFIG_DIR / "Home" / "shortcuts.json",
    "units": CONFIG_DIR / "Config" / "units.json",
    "scripts": CONFIG_DIR / "Home" / "scripts.json",
    "autoupdate": CONFIG_DIR / "Config" / "autoupdate.json",
}
DEFAULTS = {
    "flatpaks": {"packages": [], "overrides": {}},
    "autostart": [],
    "shortcuts": [],
    "units": [],
    "scripts": [],
    "autoupdate": {"enabled": False, "schedule": "Sun 04:00", "mode": "boot", "reboot": False, "flatpaks": True},
}
UNITS_DIR = CONFIG_DIR / "Config" / "units"
SCRIPTS_DIR = CONFIG_DIR / "Home" / "scripts"
UNIT_SUFFIXES = (".service", ".timer", ".socket", ".path", ".target", ".mount", ".automount")
SCRIPT_SUFFIXES = (".sh", ".bash", ".py")
POST_UPDATE_RUNNER = Path.home() / ".local" / "share" / "nixos-scripts" / "post-update"

# Keys under [Context] in a flatpak override file hold ';'-separated lists.
LIST_KEYS = {"shared", "sockets", "devices", "features", "filesystems", "persistent"}
SCHEDULES = [
    ("Every hour", "hourly"),
    ("Daily at 04:00", "*-*-* 04:00"),
    ("Weekly, Sunday 04:00", "Sun 04:00"),
    ("Monthly, the 1st at 04:00", "*-*-01 04:00"),
]


# ---------------------------------------------------------------------------
# Config files and git


def load_json(name):
    try:
        return json.loads(FILES[name].read_text())
    except (OSError, ValueError):
        return json.loads(json.dumps(DEFAULTS[name]))


def dump_json(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def save_json(name, data):
    """Write a config file; return True if it changed."""
    text = dump_json(data)
    path = FILES[name]
    try:
        if path.read_text() == text:
            return False
    except OSError:
        pass
    path.write_text(text)
    return True


def git_commit(paths, message):
    """Commit the given files or directories in the config repo; one-line result."""
    git = shutil.which("git")
    if not git:
        return "git not available; change left uncommitted"
    rel = [str(Path(p).relative_to(CONFIG_DIR)) for p in paths]
    subprocess.run([git, "add", "-A", "--"] + rel, cwd=CONFIG_DIR, check=False)
    staged = subprocess.run([git, "diff", "--cached", "--quiet", "--"] + rel, cwd=CONFIG_DIR, check=False)
    if staged.returncode == 0:
        return "nothing to commit"
    r = subprocess.run([git, "commit", "-q", "-m", message, "--"] + rel, cwd=CONFIG_DIR,
                       capture_output=True, text=True, check=False)
    if r.returncode != 0:
        return "commit failed: " + (r.stderr.strip() or r.stdout.strip())
    return f"committed: {message}"


def save_and_commit(name, data, message, log, extra_paths=()):
    changed = save_json(name, data)
    result = git_commit([FILES[name], *extra_paths], message)
    if changed or not result.startswith("nothing"):
        log(result)
        return True
    log("No changes.")
    return False


def run_capture(argv, cwd=None):
    """Run a command and return its stdout, or "" if it fails."""
    try:
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return ""


def config_user():
    """Account name from user.nix (what the config is built for)."""
    try:
        m = re.search(r'name\s*=\s*"([^"]+)"', (CONFIG_DIR / "user.nix").read_text())
        return m.group(1) if m else os.environ.get("USER", "")
    except OSError:
        return os.environ.get("USER", "")


# ---------------------------------------------------------------------------
# Flatpaks


def installed_apps(installation):
    out = run_capture(["flatpak", "list", f"--{installation}", "--app", "--columns=application"])
    return sorted({line.strip() for line in out.splitlines() if line.strip()})


def parse_override(text):
    """Turn `flatpak override --show` output into nix-flatpak's overrides shape:
    section -> key -> list (for Context lists) or string."""
    parser = configparser.ConfigParser(interpolation=None, delimiters=("=",))
    parser.optionxform = str  # keep key case
    parser.read_string(text)
    result = {}
    for section in parser.sections():
        entries = {}
        for key, value in parser.items(section):
            if section == "Context" and key in LIST_KEYS:
                items = [v for v in value.split(";") if v]
                if items:
                    entries[key] = items
            else:
                entries[key] = value
        if entries:
            result[section] = entries
    return result


def previously_installed():
    """Apps nix-flatpak has installed from the config so far, from its state
    file. None if it has never run (fresh install, before the first login)."""
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    path = state_home / "home-manager" / "gcroots" / "flatpak-state.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    apps = set()
    for entry in data.get("packages", []):
        app = entry if isinstance(entry, str) else entry.get("appId")
        if app:
            apps.add(app)
    return apps


def scan_flatpaks(old):
    """Return (config data, notes) for Apps/flatpaks.json.

    Installed apps are added. A declared app that is missing is only dropped
    when nix-flatpak had installed it before (so the user removed it); one it
    has not installed yet is just pending and stays."""
    user_apps = set(installed_apps("user"))
    system_apps = installed_apps("system")
    managed = previously_installed()
    pending, removed = set(), set()
    for app in old.get("packages", []):
        if app in user_apps:
            continue
        if managed is not None and app in managed:
            removed.add(app)
        else:
            pending.add(app)
    packages = sorted(user_apps | pending)

    overrides = {}
    glob = parse_override(run_capture(["flatpak", "override", "--user", "--show"]))
    if glob:
        overrides["global"] = glob
    elif "global" in old.get("overrides", {}) and not user_apps:
        overrides["global"] = old["overrides"]["global"]  # flatpak not set up yet; keep ours
    for app in sorted(user_apps):
        per_app = parse_override(run_capture(["flatpak", "override", "--user", "--show", app]))
        if per_app:
            overrides[app] = per_app
    for app in pending:  # nothing to read from the system yet; keep what the config says
        if app in old.get("overrides", {}):
            overrides[app] = old["overrides"][app]

    notes = []
    if pending:
        notes.append("Declared but not installed yet (kept): " + ", ".join(sorted(pending)))
    if removed:
        notes.append("Uninstalled since the last rebuild (dropped from the config): " + ", ".join(sorted(removed)))
    if system_apps:
        notes.append("Installed system-wide (not managed by the config, left alone): " + ", ".join(system_apps))
    return {"packages": packages, "overrides": overrides}, notes


def flatpak_diff(old, new):
    lines = []
    old_pkgs, new_pkgs = set(old.get("packages", [])), set(new.get("packages", []))
    lines += [f"+ {a}" for a in sorted(new_pkgs - old_pkgs)]
    lines += [f"- {a}" for a in sorted(old_pkgs - new_pkgs)]
    old_ov, new_ov = old.get("overrides", {}), new.get("overrides", {})
    lines += [f"~ permissions changed: {n}" for n in sorted(set(old_ov) | set(new_ov)) if old_ov.get(n) != new_ov.get(n)]
    return lines


# ---------------------------------------------------------------------------
# Autostart and desktop files

FIELD_CODES = re.compile(r"\s*%[fFuUdDnNickvm]")


def parse_desktop(path):
    """Read a .desktop file into {file, name, exec, icon}; None if not launchable."""
    parser = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (OSError, configparser.Error):
        return None
    if "Desktop Entry" not in parser:
        return None
    entry = parser["Desktop Entry"]
    if entry.get("Type", "Application") != "Application" or not entry.get("Exec"):
        return None
    if entry.get("NoDisplay", "false").lower() == "true" or entry.get("Hidden", "false").lower() == "true":
        return None
    return {
        "file": os.path.basename(path),
        "name": entry.get("Name", os.path.basename(path)),
        "exec": FIELD_CODES.sub("", entry.get("Exec")).strip(),
        "icon": entry.get("Icon", ""),
    }


def application_dirs():
    home = Path.home()
    dirs = []
    for base in os.environ.get("XDG_DATA_DIRS", "/run/current-system/sw/share:/usr/share").split(":"):
        if base:
            dirs.append(Path(base) / "applications")
    dirs += [
        home / ".local/share/applications",
        home / ".local/share/flatpak/exports/share/applications",
        Path("/var/lib/flatpak/exports/share/applications"),
        home / ".nix-profile/share/applications",
        Path(f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share/applications"),
    ]
    seen, out = set(), []
    for d in dirs:
        if d not in seen and d.is_dir():
            seen.add(d)
            out.append(d)
    return out


def available_apps():
    """Launchable applications on this system, one per desktop file name."""
    apps = {}
    for d in application_dirs():
        for path in sorted(d.glob("*.desktop")):
            if path.name in apps:
                continue
            entry = parse_desktop(path)
            if entry:
                apps[path.name] = entry
    return sorted(apps.values(), key=lambda e: e["name"].lower())


def import_autostart(entries):
    """Add autostart entries Plasma's own settings created (regular files in
    ~/.config/autostart) to the managed list. Returns (entries, notes)."""
    known = {e["file"] for e in entries}
    added = []
    autostart = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart"
    if autostart.is_dir():
        for path in sorted(autostart.glob("*.desktop")):
            if path.is_symlink() or path.name in known:  # symlinks are ours already
                continue
            entry = parse_desktop(path)
            if entry:
                entries = entries + [entry]
                added.append(entry["name"])
    notes = ["Autostart entries added from Plasma settings: " + ", ".join(added)] if added else []
    return sorted(entries, key=lambda e: e["name"].lower()), notes


# ---------------------------------------------------------------------------
# systemd units


def unit_wanted_by(path):
    """Targets named in the unit's [Install] WantedBy= lines."""
    parser = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (OSError, configparser.Error):
        return []
    if "Install" not in parser:
        return []
    return parser["Install"].get("WantedBy", "").split()


def add_unit(path, scope, enabled=True):
    """Copy a unit file into the repo and record it; returns the entry."""
    path = Path(path)
    if path.suffix not in UNIT_SUFFIXES:
        raise ValueError(f"{path.name} is not a systemd unit file")
    if scope not in ("system", "user"):
        raise ValueError("scope must be system or user")
    UNITS_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, UNITS_DIR / path.name)
    entry = {"file": path.name, "scope": scope, "enabled": bool(enabled), "wantedBy": unit_wanted_by(path)}
    units = [u for u in load_json("units") if u["file"] != path.name] + [entry]
    units.sort(key=lambda u: u["file"])
    save_json("units", units)
    return entry


def remove_unit(name):
    units = load_json("units")
    keep = [u for u in units if u["file"] != name]
    if len(keep) == len(units):
        return False
    save_json("units", keep)
    try:
        (UNITS_DIR / name).unlink()
    except OSError:
        pass
    return True


def commit_units(log):
    log(git_commit([FILES["units"], UNITS_DIR], "Services: update systemd units"))


def unit_status(entry):
    argv = ["systemctl"] + (["--user"] if entry["scope"] == "user" else []) + ["is-active", entry["file"]]
    out = run_capture(argv).strip()
    return out or "not loaded"


def make_timer(name, command, schedule, scope, description=""):
    """Write a <name>.service / <name>.timer pair into the repo and record them."""
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or "task"
    description = description or name
    service = (
        f"[Unit]\nDescription={description}\n\n"
        f"[Service]\nType=oneshot\nExecStart={command}\n"
    )
    timer = (
        f"[Unit]\nDescription=Run {description} on a schedule\n\n"
        f"[Timer]\nOnCalendar={schedule}\nPersistent=true\n\n"
        f"[Install]\nWantedBy=timers.target\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        s, t = Path(tmp) / f"{slug}.service", Path(tmp) / f"{slug}.timer"
        s.write_text(service)
        t.write_text(timer)
        add_unit(s, scope, enabled=True)
        return add_unit(t, scope, enabled=True)


# ---------------------------------------------------------------------------
# Scripts


def script_kind(path):
    """"python", "bash", "script" (other executable text) or "file"."""
    path = Path(path)
    if path.suffix == ".py":
        return "python"
    if path.suffix in (".sh", ".bash"):
        return "bash"
    try:
        with open(path, "rb") as f:
            head = f.read(64)
    except OSError:
        return "file"
    if head.startswith(b"#!"):
        if b"python" in head:
            return "python"
        if b"bash" in head or b"/sh" in head:
            return "bash"
        return "script"
    return "file"


def add_script(path, data=False, post_update=False):
    """Copy a script or companion file into Home/scripts/; returns the entry."""
    path = Path(path)
    SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    dest = SCRIPTS_DIR / path.name
    shutil.copyfile(path, dest)
    kind = "file" if data else script_kind(path)
    is_script = kind != "file"
    mode = dest.stat().st_mode
    dest.chmod((mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) if is_script else (mode & ~0o111))
    entry = {"file": path.name, "script": is_script, "kind": kind, "postUpdate": bool(post_update and is_script)}
    scripts = [s for s in load_json("scripts") if s["file"] != path.name] + [entry]
    scripts.sort(key=lambda s: s["file"])
    save_json("scripts", scripts)
    return entry


def remove_script(name):
    scripts = load_json("scripts")
    keep = [s for s in scripts if s["file"] != name]
    if len(keep) == len(scripts):
        return False
    save_json("scripts", keep)
    try:
        (SCRIPTS_DIR / name).unlink()
    except OSError:
        pass
    return True


def set_post_update(name, enabled):
    scripts = load_json("scripts")
    found = False
    for s in scripts:
        if s["file"] == name:
            s["postUpdate"] = bool(enabled and s["script"])
            found = True
    if found:
        save_json("scripts", scripts)
    return found


def post_update_step():
    """Run the post-update runner the config installed, if there is one."""
    return ("Running post-update scripts",
            ["bash", "-c", f'r="{POST_UPDATE_RUNNER}"; if [ -x "$r" ]; then exec "$r"; else echo "No post-update scripts configured."; fi'])


def commit_scripts(log):
    log(git_commit([FILES["scripts"], SCRIPTS_DIR], "Scripts: update scripts and files"))


def script_run_cmd(entry):
    """Command to run a script from the repo copy (works before Apply too)."""
    path = SCRIPTS_DIR / entry["file"]
    if entry.get("kind") == "python":
        return ["python3", str(path)]
    if entry.get("kind") == "bash":
        return ["bash", str(path)]
    return [str(path)]


def installed_script_path(name, scope):
    """Where the script lives after Apply, for use in units."""
    return f"%h/.local/bin/{name}" if scope == "user" else f"/home/{config_user()}/.local/bin/{name}"


# ---------------------------------------------------------------------------
# Steps: each is ("title", callable(log)) or ("title", argv). Shared by CLI and GUI.


def root_cmd(action):
    """Run the privileged helper: sudo in a terminal, polkit otherwise."""
    if sys.stdin.isatty() and shutil.which("sudo"):
        return ["sudo", str(HELPER), action, str(CONFIG_DIR)]
    return ["pkexec", str(HELPER), action, str(CONFIG_DIR)]


def step_sync(log, dry_run=False):
    """Bring flatpaks.json and autostart.json in line with the system."""
    changed = []
    old = load_json("flatpaks")
    new, notes = scan_flatpaks(old)
    for n in notes:
        log(n)
    changes = flatpak_diff(old, new)
    if changes:
        log("Flatpak changes found on this system:")
        for c in changes:
            log("  " + c)
        if not dry_run and save_json("flatpaks", new):
            changed.append(FILES["flatpaks"])
    else:
        log("Flatpak list and permissions already match the config.")

    entries, notes = import_autostart(load_json("autostart"))
    for n in notes:
        log(n)
    if notes and not dry_run and save_json("autostart", entries):
        changed.append(FILES["autostart"])

    if changed:
        log(git_commit(changed, "Sync Flatpaks and autostart entries from the system"))
    return bool(changed)


def update_steps(sync=True):
    steps = []
    if sync:
        steps.append(("Syncing Flatpaks and autostart entries", lambda log: step_sync(log)))
    steps.append(("Refreshing flake inputs", ["nix", "flake", "update", "--flake", str(CONFIG_DIR)]))
    steps.append(("Committing flake.lock", lambda log: log(git_commit([CONFIG_DIR / "flake.lock"], "Update flake inputs"))))
    steps.append(("Building and switching to the new system", root_cmd("switch")))
    steps.append(("Updating Flatpaks", ["flatpak", "update", "--user", "-y", "--noninteractive"]))
    steps.append(post_update_step())
    return steps


def apply_steps():
    return [("Building and switching to the new system", root_cmd("switch"))]


def flush_steps():
    return [
        ("Removing old home-manager and user generations", ["nix-collect-garbage", "-d"]),
        ("Removing unused Flatpak runtimes", ["flatpak", "uninstall", "--user", "--unused", "-y", "--noninteractive"]),
        ("Removing old system generations and boot entries", root_cmd("flush")),
    ]


def push_steps():
    # accept-new: a first SSH push does not stall on the host-key prompt; the
    # config also pins GitHub's key through programs.ssh.knownHosts.
    return [("Pushing the config repo",
             ["env", "GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new", "git", "push"])]


# ---------------------------------------------------------------------------
# Git remote and SSH key


def remote_url():
    """The configured origin URL (not what url.*.insteadOf would rewrite it to)."""
    return run_capture(["git", "config", "--get", "remote.origin.url"], cwd=CONFIG_DIR).strip()


def parse_remote(url):
    """(host, owner, repo) from an https or ssh GitHub-style URL."""
    m = re.search(r"([\w.-]+)[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$", url)
    if not m:
        return ("github.com", "", "nixosconf")
    return m.group(1), m.group(2), m.group(3)


def ssh_remote(username, url):
    host, _, repo = parse_remote(url)
    if host not in url:
        host = "github.com"
    return f"git@{host}:{username}/{repo}.git"


def set_remote(url):
    subprocess.run(["git", "remote", "set-url", "origin", url], cwd=CONFIG_DIR, check=False)


def ssh_public_key():
    """Text of the first usable public key in ~/.ssh, or None."""
    ssh_dir = Path.home() / ".ssh"
    for name in ("id_ed25519", "id_ecdsa", "id_rsa"):
        if (ssh_dir / name).exists() and (ssh_dir / f"{name}.pub").exists():
            try:
                return (ssh_dir / f"{name}.pub").read_text().strip()
            except OSError:
                continue
    return None


def generate_ssh_key():
    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    comment = f"{os.environ.get('USER', 'user')}@{os.uname().nodename}"
    try:
        r = subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", str(ssh_dir / "id_ed25519")],
                           capture_output=True, text=True, check=False)
    except FileNotFoundError:
        raise RuntimeError("ssh-keygen is not installed") from None
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "ssh-keygen failed")
    return ssh_public_key()


def remote_summary():
    url = remote_url()
    if not url:
        return "none"
    return f"{url}  (SSH)" if url.startswith("git@") or url.startswith("ssh://") else f"{url}  (HTTPS, Push switches it to SSH)"


def reboot_required():
    """True when the running system's kernel or initrd differ from the booted ones."""
    try:
        for part in ("kernel", "initrd", "kernel-modules"):
            if os.path.realpath(f"/run/current-system/{part}") != os.path.realpath(f"/run/booted-system/{part}"):
                return True
    except OSError:
        return False
    return False


def system_info():
    version = run_capture(["nixos-version"]).strip() or "unknown"
    gen = os.path.basename(os.path.realpath("/run/current-system"))
    return version, gen


def unpushed_commits():
    out = run_capture(["git", "rev-list", "--count", "@{upstream}..HEAD"], cwd=CONFIG_DIR).strip()
    return int(out) if out.isdigit() else 0


# ---------------------------------------------------------------------------
# CLI


def run_steps_cli(steps):
    for title, action in steps:
        print(f"\n==> {title}", flush=True)
        if callable(action):
            action(lambda line: print(line, flush=True))
            continue
        r = subprocess.run(action, cwd=CONFIG_DIR, check=False)
        if r.returncode != 0:
            print(f"==> '{title}' failed with exit code {r.returncode}", file=sys.stderr)
            return r.returncode
    return 0


def cli(args):
    echo = lambda line: print(line, flush=True)  # noqa: E731
    if args.command == "sync":
        step_sync(echo, dry_run=args.dry_run)
        return 0
    if args.command == "update":
        rc = run_steps_cli(update_steps(sync=not args.no_sync))
        if rc == 0 and reboot_required():
            print("\n==> A reboot is needed for the new kernel to take effect.")
        return rc
    if args.command == "apply":
        return run_steps_cli(apply_steps())
    if args.command == "flush":
        return run_steps_cli(flush_steps())
    if args.command == "push":
        url = remote_url()
        if not url:
            print("No git remote configured.", file=sys.stderr)
            return 1
        try:
            if url.startswith("https://"):
                _, owner, _ = parse_remote(url)
                prompt = f"Pushing uses SSH. GitHub username [{owner}]: " if owner else "GitHub username: "
                name = input(prompt).strip() or owner
                if not name:
                    return 1
                set_remote(ssh_remote(name, url))
                print(f"Remote switched to {remote_url()}")
            if ssh_public_key() is not None:
                return run_steps_cli(push_steps())
            create = input("No SSH key in ~/.ssh. Create one now? [Y/n] ").strip().lower()
        except EOFError:
            print()
            return 1
        if create in ("", "y", "yes"):
            try:
                pub = generate_ssh_key()
            except RuntimeError as e:
                print(f"Could not create a key: {e}", file=sys.stderr)
                return 1
            print("\nAdd this key at https://github.com/settings/keys, then push again:\n\n" + pub + "\n")
        return 1
    if args.command == "reboot":
        os.execvp("systemctl", ["systemctl", "reboot"])
    if args.command == "unit":
        if args.unit_command == "list":
            for u in load_json("units"):
                print(f'{u["file"]:32} {u["scope"]:7} {"enabled" if u["enabled"] else "disabled":9} {unit_status(u)}')
            return 0
        if args.unit_command == "add":
            scope = "user" if args.user else "system"
            entry = add_unit(args.file, scope, enabled=not args.disabled)
            print(f'Added {entry["file"]} as a {scope} unit, wanted by {", ".join(entry["wantedBy"]) or "nothing"}')
            commit_units(echo)
            print("Run `nixos-updater apply` to install it.")
            return 0
        if args.unit_command == "remove":
            if not remove_unit(args.name):
                print(f"{args.name} is not in the config", file=sys.stderr)
                return 1
            commit_units(echo)
            print("Run `nixos-updater apply` to remove it from the system.")
            return 0
    if args.command == "script":
        if args.script_command == "list":
            for s in load_json("scripts"):
                print(f'{s["file"]:32} {s["kind"]:7} {"on PATH" if s["script"] else "companion file":15} '
                      f'{"runs after update" if s.get("postUpdate") else ""}')
            return 0
        if args.script_command == "add":
            for f in args.files:
                entry = add_script(f, data=args.data, post_update=args.post_update)
                print(f'Added {entry["file"]} ({entry["kind"]}{", on PATH after apply" if entry["script"] else ""}'
                      f'{", runs after update" if entry["postUpdate"] else ""})')
            commit_scripts(echo)
            return 0
        if args.script_command == "post-update":
            if not set_post_update(args.name, args.state == "on"):
                print(f"{args.name} is not in the config", file=sys.stderr)
                return 1
            commit_scripts(echo)
            return 0
        if args.script_command == "remove":
            if not remove_script(args.name):
                print(f"{args.name} is not in the config", file=sys.stderr)
                return 1
            commit_scripts(echo)
            return 0
        if args.script_command == "run":
            entry = next((s for s in load_json("scripts") if s["file"] == args.name), None)
            if not entry:
                print(f"{args.name} is not in the config", file=sys.stderr)
                return 1
            return subprocess.run(script_run_cmd(entry), check=False).returncode
    return 0


# ---------------------------------------------------------------------------
# GUI


def gui(smoke_test=False):
    from PyQt6.QtCore import QProcess, QSize, Qt, QTimer
    from PyQt6.QtGui import QDesktopServices, QFontDatabase, QIcon, QKeySequence
    from PyQt6.QtCore import QUrl
    from PyQt6.QtWidgets import (QAbstractItemView, QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox,
                                 QFileDialog, QFormLayout, QFrame, QGridLayout, QHBoxLayout, QKeySequenceEdit, QLabel,
                                 QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QPlainTextEdit,
                                 QProgressBar, QPushButton, QSizePolicy, QSplitter, QStackedWidget, QTableWidget,
                                 QTableWidgetItem, QToolButton, QVBoxLayout, QWidget)

    def icon(*names):
        for name in names:
            ic = QIcon.fromTheme(name)
            if not ic.isNull():
                return ic
        return QIcon()

    def muted(text):
        label = QLabel(text)
        label.setWordWrap(True)
        label.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        f = label.font()
        f.setPointSize(max(f.pointSize() - 1, 8))
        label.setFont(f)
        label.setStyleSheet("color: palette(placeholder-text);")
        return label

    def page_header(title, subtitle):
        box = QVBoxLayout()
        box.setSpacing(2)
        t = QLabel(title)
        f = t.font()
        f.setPointSize(f.pointSize() + 4)
        f.setBold(True)
        t.setFont(f)
        box.addWidget(t)
        box.addWidget(muted(subtitle))
        return box

    def button(text, icon_names, slot, primary=False):
        b = QPushButton(icon(*icon_names), text)
        b.clicked.connect(slot)
        if primary:
            b.setDefault(True)
        return b

    def table(headers):
        t = QTableWidget(0, len(headers))
        t.setHorizontalHeaderLabels(headers)
        t.horizontalHeader().setStretchLastSection(True)
        t.verticalHeader().setVisible(False)
        t.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        t.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        t.setAlternatingRowColors(True)
        t.setShowGrid(False)
        return t

    def selected_rows(t):
        return sorted({i.row() for i in t.selectedIndexes()}, reverse=True)

    class DropTable(QTableWidget):
        """A table that accepts files with given suffixes dropped from the file manager."""

        def __init__(self, headers, suffixes, on_files, placeholder):
            super().__init__(0, len(headers))
            self.setHorizontalHeaderLabels(headers)
            self.horizontalHeader().setStretchLastSection(True)
            self.verticalHeader().setVisible(False)
            self.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.setAlternatingRowColors(True)
            self.setShowGrid(False)
            self.suffixes = suffixes
            self.on_files = on_files
            self.placeholder = placeholder
            self.setAcceptDrops(True)

        def accepts(self, event):
            return any(u.isLocalFile() and (not self.suffixes or u.toLocalFile().endswith(self.suffixes))
                       for u in event.mimeData().urls())

        def dragEnterEvent(self, event):  # noqa: N802 - Qt API
            if self.accepts(event):
                event.acceptProposedAction()

        def dragMoveEvent(self, event):  # noqa: N802 - Qt API
            event.acceptProposedAction()

        def dropEvent(self, event):  # noqa: N802 - Qt API
            paths = [u.toLocalFile() for u in event.mimeData().urls()
                     if u.isLocalFile() and (not self.suffixes or u.toLocalFile().endswith(self.suffixes))]
            if paths:
                event.acceptProposedAction()
                self.on_files(paths)

        def paintEvent(self, event):  # noqa: N802 - Qt API
            super().paintEvent(event)
            if self.rowCount() == 0:
                from PyQt6.QtGui import QPainter
                p = QPainter(self.viewport())
                p.setPen(self.palette().placeholderText().color())
                p.drawText(self.viewport().rect(), Qt.AlignmentFlag.AlignCenter, self.placeholder)

    # -- dialogs

    class PickAppDialog(QDialog):
        def __init__(self, parent):
            super().__init__(parent)
            self.setWindowTitle("Add application to autostart")
            self.resize(480, 520)
            layout = QVBoxLayout(self)
            self.filter = QLineEdit()
            self.filter.setPlaceholderText("Filter…")
            self.filter.setClearButtonEnabled(True)
            layout.addWidget(self.filter)
            self.list = QListWidget()
            for app in available_apps():
                item = QListWidgetItem(icon(app["icon"], "application-x-executable"), app["name"])
                item.setData(Qt.ItemDataRole.UserRole, app)
                item.setToolTip(app["exec"])
                self.list.addItem(item)
            self.filter.textChanged.connect(self.apply_filter)
            self.list.itemDoubleClicked.connect(lambda _: self.accept())
            layout.addWidget(self.list, 1)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)

        def apply_filter(self, text):
            text = text.lower()
            for i in range(self.list.count()):
                item = self.list.item(i)
                item.setHidden(text not in item.text().lower() and text not in item.toolTip().lower())

        def chosen(self):
            item = self.list.currentItem()
            return item.data(Qt.ItemDataRole.UserRole) if item else None

    class CommandDialog(QDialog):
        """Name + command, optionally with a shortcut recorder."""

        def __init__(self, parent, title, with_shortcut):
            super().__init__(parent)
            self.setWindowTitle(title)
            self.resize(440, 0)
            form = QFormLayout(self)
            self.name = QLineEdit()
            self.command = QLineEdit()
            form.addRow("Name", self.name)
            if with_shortcut:
                self.key = QKeySequenceEdit()
                form.addRow("Shortcut", self.key)
            self.command.setPlaceholderText("e.g. kitty, or flatpak run org.signal.Signal")
            form.addRow("Command", self.command)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            form.addRow(buttons)

    class TimerDialog(QDialog):
        """Create a service + timer pair."""

        def __init__(self, parent, scope):
            super().__init__(parent)
            self.scope = scope
            self.setWindowTitle("New timer")
            self.resize(480, 0)
            form = QFormLayout(self)
            self.name = QLineEdit()
            self.name.setPlaceholderText("e.g. nightly-backup")
            form.addRow("Name", self.name)
            self.command = QLineEdit()
            self.command.setPlaceholderText("Command to run, with an absolute path")
            form.addRow("Command", self.command)
            scripts = [s for s in load_json("scripts") if s["script"]]
            if scripts:
                self.script = QComboBox()
                self.script.addItem("Pick a script from the Scripts page…", "")
                for s in scripts:
                    self.script.addItem(s["file"], installed_script_path(s["file"], scope))
                self.script.currentIndexChanged.connect(
                    lambda i: self.command.setText(self.script.currentData()) if self.script.currentData() else None)
                form.addRow("Script", self.script)
            self.schedule = QComboBox()
            for label, _ in SCHEDULES:
                self.schedule.addItem(label)
            self.schedule.addItem("Custom (systemd OnCalendar)")
            self.custom = QLineEdit()
            self.custom.setPlaceholderText("e.g. Mon..Fri 18:00")
            self.custom.setEnabled(False)
            self.schedule.currentIndexChanged.connect(lambda i: self.custom.setEnabled(i == len(SCHEDULES)))
            form.addRow("When", self.schedule)
            form.addRow("Custom", self.custom)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            form.addRow(buttons)

        def values(self):
            i = self.schedule.currentIndex()
            schedule = SCHEDULES[i][1] if i < len(SCHEDULES) else self.custom.text().strip()
            return self.name.text().strip(), self.command.text().strip(), schedule

    # -- pages

    class Page(QWidget):
        """A settings page: header, body, action row. Subclasses fill body()."""

        title = ""
        subtitle = ""

        def __init__(self, window):
            super().__init__()
            self.window = window
            self.layout_ = QVBoxLayout(self)
            self.layout_.setContentsMargins(24, 20, 24, 16)
            self.layout_.setSpacing(12)
            self.layout_.addLayout(page_header(self.title, self.subtitle))
            self.body()

        def actions(self, *buttons, save=None):
            row = QHBoxLayout()
            for b in buttons:
                row.addWidget(b)
            row.addStretch(1)
            if save:
                row.addWidget(button("Save", ["document-save"], save, primary=True))
            self.layout_.addLayout(row)

        def log(self, text):
            self.window.log(text)

    class OverviewPage(Page):
        title = "Overview"
        subtitle = "Everything here changes the config in the repo first; Apply or Update makes it real."

        def body(self):
            card = QFrame()
            card.setFrameShape(QFrame.Shape.StyledPanel)
            grid = QGridLayout(card)
            version, gen = system_info()
            self.facts = {}
            rows = [
                ("System", version),
                ("Generation", gen),
                ("Config", str(CONFIG_DIR)),
                ("Flatpaks declared", str(len(load_json("flatpaks").get("packages", [])))),
                ("Unpushed commits", str(unpushed_commits())),
                ("Remote", remote_summary()),
            ]
            for r, (k, v) in enumerate(rows):
                grid.addWidget(muted(k), r, 0)
                lab = QLabel(v)
                lab.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
                self.facts[k] = lab
                grid.addWidget(lab, r, 1)
            grid.setColumnStretch(1, 1)
            self.layout_.addWidget(card)

            grid = QGridLayout()
            grid.setSpacing(12)
            actions = [
                ("Update", ["system-software-update", "update-none"], self.window.update,
                 "Sync, refresh flake inputs, rebuild, update Flatpaks"),
                ("Apply", ["dialog-ok-apply", "system-run"], self.window.apply,
                 "Rebuild from the config as it is saved now"),
                ("Sync", ["flatpak-discover", "view-refresh"], self.window.sync,
                 "Record installed Flatpaks, permissions and autostart entries"),
                ("Push", ["vcs-push", "cloud-upload", "go-up"], self.window.push, "Send commits to GitHub"),
                ("Flush", ["edit-clear-history", "user-trash"], self.window.flush,
                 "Remove old generations, boot entries, unused Flatpak runtimes"),
                ("Reboot", ["system-reboot"], self.window.reboot, "Restart the machine"),
            ]
            self.window.buttons = []
            for i, (text, icons, slot, tip) in enumerate(actions):
                b = QToolButton()
                b.setText(text)
                b.setIcon(icon(*icons))
                b.setIconSize(QSize(40, 40))
                b.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextUnderIcon)
                b.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
                b.setMinimumHeight(96)
                b.setToolTip(tip)
                b.clicked.connect(slot)
                cell = QVBoxLayout()
                cell.setSpacing(4)
                cell.addWidget(b)
                cell.addWidget(muted(tip))
                grid.addLayout(cell, i // 3, i % 3)
                self.window.buttons.append(b)
            self.layout_.addLayout(grid)
            self.layout_.addStretch(1)

        def refresh(self):
            version, gen = system_info()
            self.facts["System"].setText(version)
            self.facts["Generation"].setText(gen)
            self.facts["Flatpaks declared"].setText(str(len(load_json("flatpaks").get("packages", []))))
            self.facts["Unpushed commits"].setText(str(unpushed_commits()))
            self.facts["Remote"].setText(remote_summary())

    class FlatpaksPage(Page):
        title = "Flatpaks"
        subtitle = ("What the config declares. Install and remove apps with Bazaar, change permissions in Flatseal or "
                    "Plasma's Flatpak settings, then Sync to record it; Update does this on its own.")

        def body(self):
            self.table = table(["Application", "Custom permissions"])
            self.layout_.addWidget(self.table, 1)
            self.actions(button("Sync now", ["view-refresh"], self.window.sync),
                         button("Open Bazaar", ["io.github.kolunmi.Bazaar", "flatpak-discover"],
                                lambda: subprocess.Popen(["bazaar"])))
            self.refresh()

        def refresh(self):
            data = load_json("flatpaks")
            self.table.setRowCount(0)
            for app in data.get("packages", []):
                r = self.table.rowCount()
                self.table.insertRow(r)
                self.table.setItem(r, 0, QTableWidgetItem(icon(app, "application-x-executable"), app))
                ov = data.get("overrides", {}).get(app, {})
                summary = ", ".join(f"{k}: {len(v)}" for k, v in ov.items()) if ov else ""
                self.table.setItem(r, 1, QTableWidgetItem(summary))
            self.table.resizeColumnToContents(0)

    class AutostartPage(Page):
        title = "Autostart"
        subtitle = "Applications and commands started with your Plasma session."

        def body(self):
            self.entries = load_json("autostart")
            self.table = table(["Name", "Command"])
            self.layout_.addWidget(self.table, 1)
            self.actions(button("Add application…", ["list-add"], self.add_app),
                         button("Add command…", ["utilities-terminal"], self.add_cmd),
                         button("Remove", ["list-remove"], self.remove), save=self.save)
            self.refresh()

        def refresh(self):
            self.table.setRowCount(0)
            for e in self.entries:
                r = self.table.rowCount()
                self.table.insertRow(r)
                self.table.setItem(r, 0, QTableWidgetItem(icon(e.get("icon", ""), "application-x-executable"), e["name"]))
                self.table.setItem(r, 1, QTableWidgetItem(e["exec"]))
            self.table.resizeColumnToContents(0)

        def add_entry(self, entry):
            self.entries = [e for e in self.entries if e["file"] != entry["file"]] + [entry]
            self.entries.sort(key=lambda e: e["name"].lower())
            self.refresh()

        def add_app(self):
            d = PickAppDialog(self)
            if d.exec() and d.chosen():
                self.add_entry(d.chosen())

        def add_cmd(self):
            d = CommandDialog(self, "Add command to autostart", with_shortcut=False)
            if d.exec() and d.name.text().strip() and d.command.text().strip():
                name = d.name.text().strip()
                slug = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-").lower() or "command"
                self.add_entry({"file": f"{slug}.desktop", "name": name, "exec": d.command.text().strip(),
                                "icon": "utilities-terminal"})

        def remove(self):
            for r in selected_rows(self.table):
                del self.entries[r]
            self.refresh()

        def save(self):
            self.log("\n==> Saving autostart entries")
            if save_and_commit("autostart", self.entries, "Autostart: update entries", self.log):
                self.window.needs_apply()

    class ShortcutsPage(Page):
        title = "Shortcuts"
        subtitle = "Global shortcuts that run a command. They take effect after the next rebuild and login."

        def body(self):
            self.entries = load_json("shortcuts")
            self.table = table(["Name", "Shortcut", "Command"])
            self.layout_.addWidget(self.table, 1)
            self.actions(button("Add shortcut…", ["list-add"], self.add),
                         button("Remove", ["list-remove"], self.remove), save=self.save)
            self.refresh()

        def refresh(self):
            self.table.setRowCount(0)
            for e in self.entries:
                r = self.table.rowCount()
                self.table.insertRow(r)
                for c, key in enumerate(("name", "key", "command")):
                    self.table.setItem(r, c, QTableWidgetItem(e.get(key, "")))
            self.table.resizeColumnsToContents()

        def add(self):
            d = CommandDialog(self, "Add shortcut", with_shortcut=True)
            if not d.exec():
                return
            name, command = d.name.text().strip(), d.command.text().strip()
            key = d.key.keySequence().toString(QKeySequence.SequenceFormat.PortableText)
            if not (name and command and key):
                QMessageBox.warning(self, "Add shortcut", "Name, shortcut and command are all needed.")
                return
            self.entries = [e for e in self.entries if e["name"].lower() != name.lower()]
            self.entries.append({"name": name, "key": key, "command": command})
            self.entries.sort(key=lambda e: e["name"].lower())
            self.refresh()

        def remove(self):
            for r in selected_rows(self.table):
                del self.entries[r]
            self.refresh()

        def save(self):
            self.log("\n==> Saving shortcuts")
            if save_and_commit("shortcuts", self.entries, "Shortcuts: update custom command shortcuts", self.log):
                self.window.needs_apply()

    class UnitsPage(Page):
        scope = "system"

        def body(self):
            self.table = DropTable(["Unit", "Enabled", "Wanted by", "Status"], UNIT_SUFFIXES, self.add_files,
                                   "Drop .service or .timer files here")
            self.table.itemChanged.connect(self.toggled)
            self.layout_.addWidget(self.table, 1)
            self.actions(button("Add unit file…", ["list-add"], self.add_dialog),
                         button("New timer…", ["chronometer", "appointment-new"], self.new_timer),
                         button("Remove", ["list-remove"], self.remove),
                         button("Refresh status", ["view-refresh"], self.refresh), save=self.save)
            self.refresh()

        def units(self):
            return [u for u in load_json("units") if u["scope"] == self.scope]

        def refresh(self):
            self.rows = self.units()
            self.table.blockSignals(True)
            self.table.setRowCount(0)
            for u in self.rows:
                r = self.table.rowCount()
                self.table.insertRow(r)
                self.table.setItem(r, 0, QTableWidgetItem(icon("chronometer" if u["file"].endswith(".timer") else "system-run"), u["file"]))
                enabled = QTableWidgetItem()
                enabled.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                enabled.setCheckState(Qt.CheckState.Checked if u["enabled"] else Qt.CheckState.Unchecked)
                self.table.setItem(r, 1, enabled)
                self.table.setItem(r, 2, QTableWidgetItem(", ".join(u["wantedBy"]) or "—"))
                self.table.setItem(r, 3, QTableWidgetItem(unit_status(u)))
            self.table.resizeColumnsToContents()
            self.table.blockSignals(False)

        def toggled(self, item):
            if item.column() == 1 and item.row() < len(self.rows):
                name = self.rows[item.row()]["file"]
                units = load_json("units")
                for u in units:
                    if u["file"] == name:
                        u["enabled"] = item.checkState() == Qt.CheckState.Checked
                save_json("units", units)

        def add_files(self, paths):
            for path in paths:
                try:
                    entry = add_unit(path, self.scope)
                except (OSError, ValueError) as e:
                    QMessageBox.warning(self, "Add unit", str(e))
                    continue
                self.log(f'Added {entry["file"]} ({self.scope} unit, wanted by {", ".join(entry["wantedBy"]) or "nothing"})')
            self.refresh()

        def add_dialog(self):
            paths, _ = QFileDialog.getOpenFileNames(self, "Add systemd unit files", str(Path.home()),
                                                    "systemd units (*.service *.timer *.socket *.path *.target *.mount)")
            if paths:
                self.add_files(paths)

        def new_timer(self):
            d = TimerDialog(self, self.scope)
            if not d.exec():
                return
            name, command, schedule = d.values()
            if not (name and command and schedule):
                QMessageBox.warning(self, "New timer", "Name, command and schedule are all needed.")
                return
            entry = make_timer(name, command, schedule, self.scope)
            self.log(f'Created {entry["file"]} and its service ({self.scope}), schedule: {schedule}')
            self.refresh()

        def remove(self):
            for r in selected_rows(self.table):
                remove_unit(self.rows[r]["file"])
            self.refresh()

        def save(self):
            self.log("\n==> Saving systemd units")
            commit_units(self.log)
            self.window.needs_apply()

    class SystemUnitsPage(UnitsPage):
        title = "System Units"
        subtitle = ("systemd units installed for the whole machine. Drop .service or .timer files, or create a "
                    "timer. The file is kept in Config/units/ and starts at boot when Enabled is ticked.")
        scope = "system"

    class UserUnitsPage(UnitsPage):
        title = "User Units"
        subtitle = ("home-manager units that run inside your session as you. Timers here can use %h for your "
                    "home directory. The file is kept in Config/units/.")
        scope = "user"

    class ScriptsPage(Page):
        title = "Scripts"
        subtitle = ("Bash or Python scripts and the files they need. Kept in Home/scripts/, installed to "
                    "~/.local/share/nixos-scripts/, and scripts also go on your PATH via ~/.local/bin. A script finds "
                    "its companion files in its own directory. Tick \"After update\" to run a script at the end of "
                    "every Update, including unattended ones.")

        def body(self):
            self.table = DropTable(["File", "Kind", "On PATH", "After update"], (), self.add_files,
                                   "Drop scripts and their files here")
            self.table.itemChanged.connect(self.toggled)
            self.layout_.addWidget(self.table, 1)
            self.actions(button("Add script…", ["list-add"], lambda: self.add_dialog(False)),
                         button("Add companion file…", ["document-new"], lambda: self.add_dialog(True)),
                         button("Run", ["media-playback-start"], self.run),
                         button("Edit", ["document-edit"], self.edit),
                         button("Remove", ["list-remove"], self.remove), save=self.save)
            self.refresh()

        def refresh(self):
            self.rows = load_json("scripts")
            self.table.blockSignals(True)
            self.table.setRowCount(0)
            for s in self.rows:
                r = self.table.rowCount()
                self.table.insertRow(r)
                ic = {"python": "text-x-python", "bash": "text-x-script", "script": "text-x-script"}.get(s["kind"], "text-x-generic")
                self.table.setItem(r, 0, QTableWidgetItem(icon(ic), s["file"]))
                self.table.setItem(r, 1, QTableWidgetItem(s["kind"]))
                self.table.setItem(r, 2, QTableWidgetItem("yes" if s["script"] else "companion file"))
                after = QTableWidgetItem()
                if s["script"]:
                    after.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                    after.setCheckState(Qt.CheckState.Checked if s.get("postUpdate") else Qt.CheckState.Unchecked)
                else:
                    after.setFlags(Qt.ItemFlag.ItemIsSelectable)
                    after.setText("—")
                self.table.setItem(r, 3, after)
            self.table.resizeColumnsToContents()
            self.table.blockSignals(False)

        def toggled(self, item):
            if item.column() == 3 and item.row() < len(self.rows) and self.rows[item.row()]["script"]:
                set_post_update(self.rows[item.row()]["file"], item.checkState() == Qt.CheckState.Checked)

        def add_files(self, paths, data=False):
            for path in paths:
                try:
                    entry = add_script(path, data=data)
                except OSError as e:
                    QMessageBox.warning(self, "Add script", str(e))
                    continue
                self.log(f'Added {entry["file"]} ({entry["kind"]}{", on PATH after Apply" if entry["script"] else ""})')
            self.refresh()

        def add_dialog(self, data):
            paths, _ = QFileDialog.getOpenFileNames(self, "Add companion files" if data else "Add scripts", str(Path.home()),
                                                    "All files (*)" if data else "Scripts (*.sh *.bash *.py);;All files (*)")
            if paths:
                self.add_files(paths, data=data)

        def selected(self):
            rows = selected_rows(self.table)
            return self.rows[rows[-1]] if rows else None

        def run(self):
            s = self.selected()
            if not s:
                return
            if not s["script"]:
                QMessageBox.information(self, "Run", f'{s["file"]} is a companion file, not a script.')
                return
            self.window.run([(f'Running {s["file"]}', script_run_cmd(s))], f'{s["file"]} finished.')

        def edit(self):
            s = self.selected()
            if s:
                QDesktopServices.openUrl(QUrl.fromLocalFile(str(SCRIPTS_DIR / s["file"])))

        def remove(self):
            for r in selected_rows(self.table):
                remove_script(self.rows[r]["file"])
            self.refresh()

        def save(self):
            self.log("\n==> Saving scripts")
            commit_scripts(self.log)
            self.window.needs_apply()

    class AutoUpdatePage(Page):
        title = "Auto Updates"
        subtitle = ("Unattended updates run by a systemd timer: refresh flake inputs, rebuild, update Flatpaks. "
                    "Missed runs happen at the next boot.")

        def body(self):
            self.data = load_json("autoupdate")
            form = QFormLayout()
            form.setHorizontalSpacing(16)
            self.enabled = QCheckBox("Enable automatic updates")
            self.enabled.setChecked(bool(self.data.get("enabled")))
            form.addRow(self.enabled)
            self.schedule = QComboBox()
            presets = [s for _, s in SCHEDULES if s != "hourly"]
            for label, s in SCHEDULES:
                if s != "hourly":
                    self.schedule.addItem(label)
            self.schedule.addItem("Custom (systemd OnCalendar)")
            self.custom = QLineEdit()
            self.custom.setPlaceholderText("e.g. Mon,Fri 03:30")
            current = self.data.get("schedule", "Sun 04:00")
            if current in presets:
                self.schedule.setCurrentIndex(presets.index(current))
            else:
                self.schedule.setCurrentIndex(len(presets))
                self.custom.setText(current)
            self.presets = presets
            self.schedule.currentIndexChanged.connect(lambda i: self.custom.setEnabled(i == len(self.presets)))
            self.custom.setEnabled(self.schedule.currentIndex() == len(presets))
            form.addRow("When", self.schedule)
            form.addRow("Custom", self.custom)
            self.mode = QComboBox()
            self.mode.addItem("Build now, use at next boot (safer)", "boot")
            self.mode.addItem("Switch immediately", "switch")
            self.mode.setCurrentIndex(0 if self.data.get("mode", "boot") == "boot" else 1)
            form.addRow("Mode", self.mode)
            self.flatpaks = QCheckBox("Also update Flatpaks")
            self.flatpaks.setChecked(bool(self.data.get("flatpaks", True)))
            form.addRow(self.flatpaks)
            self.reboot = QCheckBox("Reboot automatically when the kernel changed")
            self.reboot.setChecked(bool(self.data.get("reboot")))
            form.addRow(self.reboot)
            self.layout_.addLayout(form)
            self.layout_.addStretch(1)
            self.actions(save=self.save)

        def save(self):
            i = self.schedule.currentIndex()
            schedule = self.presets[i] if i < len(self.presets) else self.custom.text().strip()
            if not schedule:
                QMessageBox.warning(self, "Auto updates", "Enter a schedule.")
                return
            self.data = {"enabled": self.enabled.isChecked(), "schedule": schedule, "mode": self.mode.currentData(),
                         "reboot": self.reboot.isChecked(), "flatpaks": self.flatpaks.isChecked()}
            self.log("\n==> Saving auto update settings")
            if save_and_commit("autoupdate", self.data, "Auto updates: change schedule", self.log):
                self.window.needs_apply()

    # -- main window

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle(APP_NAME)
            self.setWindowIcon(icon(APP_ID, "system-software-update"))
            self.resize(1100, 760)
            self.process = None
            self.queue = []
            self.current_title = ""
            self.done_message = ""
            self.buttons = []

            root = QWidget()
            self.setCentralWidget(root)
            outer = QVBoxLayout(root)
            outer.setContentsMargins(0, 0, 0, 0)
            outer.setSpacing(0)

            # Banner (reboot needed / changes to apply)
            self.banner = QFrame()
            self.banner.setFrameShape(QFrame.Shape.StyledPanel)
            bl = QHBoxLayout(self.banner)
            bl.setContentsMargins(16, 8, 16, 8)
            self.banner_icon = QLabel()
            bl.addWidget(self.banner_icon)
            self.banner_text = QLabel()
            bl.addWidget(self.banner_text, 1)
            self.banner_button = QPushButton()
            bl.addWidget(self.banner_button)
            self.banner.setVisible(False)
            outer.addWidget(self.banner)

            # Sidebar + pages
            split = QSplitter(Qt.Orientation.Vertical)
            top = QWidget()
            tl = QHBoxLayout(top)
            tl.setContentsMargins(0, 0, 0, 0)
            tl.setSpacing(0)
            self.nav = QListWidget()
            self.nav.setIconSize(QSize(22, 22))
            self.nav.setFixedWidth(190)
            self.nav.setFrameShape(QFrame.Shape.NoFrame)
            self.nav.setSpacing(2)
            self.pages = QStackedWidget()
            self.page_objects = []
            for cls, icons in [
                (OverviewPage, ["nix-snowflake", "computer"]),
                (FlatpaksPage, ["flatpak-discover", "package-x-generic"]),
                (AutostartPage, ["preferences-desktop-startup", "system-run"]),
                (ShortcutsPage, ["preferences-desktop-keyboard", "input-keyboard"]),
                (SystemUnitsPage, ["preferences-system-services", "system-run"]),
                (UserUnitsPage, ["user-identity", "system-users"]),
                (ScriptsPage, ["text-x-script", "utilities-terminal"]),
                (AutoUpdatePage, ["chronometer", "appointment-new"]),
            ]:
                page = cls(self)
                self.page_objects.append(page)
                self.pages.addWidget(page)
                item = QListWidgetItem(icon(*icons), cls.title)
                item.setSizeHint(QSize(0, 36))
                self.nav.addItem(item)
            self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
            self.nav.setCurrentRow(0)
            tl.addWidget(self.nav)
            tl.addWidget(self.pages, 1)
            split.addWidget(top)

            # Activity log
            bottom = QWidget()
            bl2 = QVBoxLayout(bottom)
            bl2.setContentsMargins(16, 6, 16, 8)
            bl2.setSpacing(4)
            head = QHBoxLayout()
            self.status = QLabel("Ready")
            head.addWidget(QLabel("Activity"))
            head.addStretch(1)
            head.addWidget(self.status)
            bl2.addLayout(head)
            self.log_view = QPlainTextEdit()
            self.log_view.setReadOnly(True)
            self.log_view.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            self.log_view.setMaximumBlockCount(5000)
            bl2.addWidget(self.log_view, 1)
            self.progress = QProgressBar()
            self.progress.setRange(0, 0)
            self.progress.setFixedHeight(6)
            self.progress.setTextVisible(False)
            self.progress.setVisible(False)
            bl2.addWidget(self.progress)
            split.addWidget(bottom)
            split.setStretchFactor(0, 3)
            split.setStretchFactor(1, 1)
            split.setSizes([560, 200])
            outer.addWidget(split, 1)

            self.log(f"Config: {CONFIG_DIR}")
            self.refresh_banner()

        # -- helpers
        def log(self, text):
            self.log_view.appendPlainText(text.rstrip("\n"))

        def set_busy(self, busy, message=""):
            for b in self.buttons:
                b.setEnabled(not busy)
            self.progress.setVisible(busy)
            self.status.setText(message or ("Working…" if busy else "Ready"))

        def refresh_pages(self):
            for p in self.page_objects:
                if hasattr(p, "refresh"):
                    p.refresh()

        def refresh_banner(self):
            if reboot_required():
                self.show_banner("system-reboot", "A newer kernel is installed. Reboot to start using it.", "Reboot now", self.reboot)
            else:
                self.banner.setVisible(False)

        def show_banner(self, icon_name, text, button_text, slot):
            self.banner_icon.setPixmap(icon(icon_name).pixmap(22, 22))
            self.banner_text.setText(text)
            self.banner_button.setText(button_text)
            try:
                self.banner_button.clicked.disconnect()
            except TypeError:
                pass
            self.banner_button.clicked.connect(slot)
            self.banner.setVisible(True)

        def needs_apply(self):
            self.log("Saved and committed. Apply (or Update) activates it.")
            self.refresh_pages()
            if not reboot_required():
                self.show_banner("dialog-ok-apply", "Changes are saved in the config. Rebuild to activate them.", "Apply now", self.apply)

        # -- step runner
        def run(self, steps, done_message):
            if self.process is not None:
                return
            self.queue = list(steps)
            self.done_message = done_message
            self.set_busy(True)
            self.next_step()

        def next_step(self):
            if not self.queue:
                self.finish(0)
                return
            title, action = self.queue.pop(0)
            self.current_title = title
            self.log(f"\n==> {title}")
            self.status.setText(title)
            if callable(action):
                try:
                    action(self.log)
                except Exception as e:  # noqa: BLE001 - show anything to the user
                    self.log(f"error: {e}")
                    self.finish(1)
                    return
                QTimer.singleShot(0, self.next_step)
                return
            p = QProcess(self)
            p.setWorkingDirectory(str(CONFIG_DIR))
            p.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
            p.readyReadStandardOutput.connect(lambda: self.log(bytes(p.readAllStandardOutput()).decode(errors="replace")))
            p.finished.connect(self.step_finished)
            p.errorOccurred.connect(lambda err: self.log(f"could not run {action[0]}: {err.name}"))
            self.process = p
            p.start(action[0], action[1:])

        def step_finished(self, code, _status):
            self.process = None
            if code != 0:
                self.log(f"==> '{self.current_title}' failed with exit code {code}")
                self.finish(code)
                return
            self.next_step()

        def finish(self, code):
            self.process = None
            self.queue = []
            self.set_busy(False, "Done" if code == 0 else "Failed")
            self.refresh_pages()
            self.refresh_banner()
            if code == 0:
                self.log("\n" + self.done_message)
                if self.banner.isVisible():
                    self.log("A reboot is needed for the new kernel to take effect.")
            else:
                self.log("\nStopped. Fix the problem above and try again.")

        # -- actions
        def update(self):
            self.run(update_steps(), "System update finished.")

        def apply(self):
            self.run(apply_steps(), "Rebuild finished.")

        def sync(self):
            self.run([("Syncing Flatpaks and autostart entries", lambda log: step_sync(log))], "Sync finished.")

        def push(self):
            from PyQt6.QtWidgets import QInputDialog
            url = remote_url()
            if not url:
                self.log("No git remote configured.")
                return
            if url.startswith("https://"):
                _, owner, _ = parse_remote(url)
                name, ok = QInputDialog.getText(self, "Push over SSH",
                                                "Pushing uses SSH with the key in ~/.ssh.\nGitHub username:", text=owner)
                if not ok or not name.strip():
                    return
                set_remote(ssh_remote(name.strip(), url))
                self.log(f"Remote switched to {remote_url()}")
                self.refresh_pages()
            if ssh_public_key() is None:
                if QMessageBox.question(self, "SSH key", "No SSH key found in ~/.ssh. Create one now?") != QMessageBox.StandardButton.Yes:
                    return
                try:
                    pub = generate_ssh_key()
                except RuntimeError as e:
                    QMessageBox.warning(self, "SSH key", str(e))
                    return
                self.show_public_key(pub)
                return
            self.run(push_steps(), "Push finished.")

        def show_public_key(self, pub):
            d = QDialog(self)
            d.setWindowTitle("Add your SSH key to GitHub")
            layout = QVBoxLayout(d)
            layout.addWidget(QLabel("A new key was created in ~/.ssh. Add it at github.com → Settings → SSH and GPG keys, "
                                    "then press Push again."))
            text = QPlainTextEdit(pub)
            text.setReadOnly(True)
            text.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            layout.addWidget(text)
            row = QHBoxLayout()
            copy = QPushButton(icon("edit-copy"), "Copy key")
            copy.clicked.connect(lambda: QApplication.clipboard().setText(pub))
            open_gh = QPushButton(icon("internet-services"), "Open GitHub settings")
            open_gh.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/settings/keys")))
            row.addWidget(copy)
            row.addWidget(open_gh)
            row.addStretch(1)
            close = QPushButton("Close")
            close.clicked.connect(d.accept)
            row.addWidget(close)
            layout.addLayout(row)
            d.resize(640, 220)
            d.exec()

        def flush(self):
            if QMessageBox.question(self, "Flush", "Remove all old system and home-manager generations, "
                                    "old boot entries and unused Flatpak runtimes?") != QMessageBox.StandardButton.Yes:
                return
            self.run(flush_steps(), "Flush finished.")

        def reboot(self):
            if QMessageBox.question(self, "Reboot", "Reboot now?") != QMessageBox.StandardButton.Yes:
                return
            subprocess.Popen(["systemctl", "reboot"])

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(icon(APP_ID, "system-software-update"))
    win = Window()
    win.show()
    if smoke_test:
        QTimer.singleShot(0, lambda: [win.nav.setCurrentRow(i) for i in range(win.nav.count())])
        QTimer.singleShot(300, app.quit)
    return app.exec()


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(prog=APP_ID, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("gui", help="open the window (default)").add_argument("--smoke-test", action="store_true", help=argparse.SUPPRESS)
    up = sub.add_parser("update", help="sync, refresh inputs, rebuild, update flatpaks")
    up.add_argument("--no-sync", action="store_true", help="skip the flatpak and autostart sync")
    sc = sub.add_parser("sync", help="import installed flatpaks, permissions and autostart entries into the config")
    sc.add_argument("--dry-run", action="store_true", help="only show what would change")
    sub.add_parser("apply", help="rebuild from the config as it is now")
    sub.add_parser("flush", help="remove old generations and unused flatpaks")
    sub.add_parser("push", help="git push the config repo")
    sub.add_parser("reboot", help="reboot")
    unit = sub.add_parser("unit", help="manage systemd units kept in the config").add_subparsers(dest="unit_command")
    ua = unit.add_parser("add", help="copy a unit file into the config")
    ua.add_argument("file")
    ua.add_argument("--user", action="store_true", help="install as a user unit instead of a system unit")
    ua.add_argument("--disabled", action="store_true", help="install but do not enable")
    unit.add_parser("remove", help="remove a unit from the config").add_argument("name")
    unit.add_parser("list", help="list units and their status")
    script = sub.add_parser("script", help="manage scripts kept in the config").add_subparsers(dest="script_command")
    sa = script.add_parser("add", help="copy scripts (or companion files with --data) into the config")
    sa.add_argument("files", nargs="+")
    sa.add_argument("--data", action="store_true", help="add as companion files, not executable scripts")
    sa.add_argument("--post-update", action="store_true", help="run the script after every update")
    pu = script.add_parser("post-update", help="turn running a script after updates on or off")
    pu.add_argument("name")
    pu.add_argument("state", choices=["on", "off"])
    script.add_parser("remove", help="remove a script or file from the config").add_argument("name")
    script.add_parser("run", help="run a script from the config").add_argument("name")
    script.add_parser("list", help="list scripts and files")
    args = parser.parse_args()
    if args.command in (None, "gui"):
        return gui(smoke_test=getattr(args, "smoke_test", False))
    return cli(args)


if __name__ == "__main__":
    sys.exit(main())
