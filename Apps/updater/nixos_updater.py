#!/usr/bin/env python3
"""NixOS Updater: update this machine from its flake, keep the Flatpak list in
the config in sync with what is installed, flush old generations, reboot.

GUI by default (Qt, follows the Plasma style). Subcommands for the terminal:

    nixos-updater update [--no-scan]   scan flatpaks, refresh inputs, rebuild
    nixos-updater scan [--dry-run]     write Apps/flatpaks.json from the system
    nixos-updater flush                remove old generations and unused flatpaks
    nixos-updater reboot
"""

import argparse
import configparser
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

APP_NAME = "NixOS Updater"
APP_ID = "nixos-updater"
FLAKE_HOST = "nixos"
CONFIG_LINK = os.environ.get("NIXOS_UPDATER_CONFIG", "/etc/nixos")
CONFIG_DIR = Path(os.path.realpath(CONFIG_LINK))
FLATPAK_JSON = CONFIG_DIR / "Apps" / "flatpaks.json"
HELPER = Path(__file__).resolve().parent.parent / "libexec" / "nixos-updater-helper"

# Keys under [Context] in a flatpak override file hold ';'-separated lists.
LIST_KEYS = {"shared", "sockets", "devices", "features", "filesystems", "persistent"}


# ---------------------------------------------------------------------------
# Flatpak scanning (pure functions, no Qt)


def run_capture(argv, cwd=None):
    """Run a command and return its stdout, or "" if it fails."""
    try:
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return ""


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


def scan_system(old=None):
    """Return (config data, notes). The data is what Apps/flatpaks.json holds.

    Installed apps are added. A declared app that is missing is only dropped
    when nix-flatpak had installed it before (so the user removed it); one it
    has not installed yet is just pending and stays."""
    old = old or {"packages": [], "overrides": {}}
    user_apps = set(installed_apps("user"))
    system_apps = installed_apps("system")
    managed = previously_installed()
    pending = set()
    removed = set()
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


def load_config():
    try:
        return json.loads(FLATPAK_JSON.read_text())
    except (OSError, ValueError):
        return {"packages": [], "overrides": {}}


def dump_config(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def diff_summary(old, new):
    lines = []
    old_pkgs, new_pkgs = set(old.get("packages", [])), set(new.get("packages", []))
    for app in sorted(new_pkgs - old_pkgs):
        lines.append(f"+ {app}")
    for app in sorted(old_pkgs - new_pkgs):
        lines.append(f"- {app}")
    old_ov, new_ov = old.get("overrides", {}), new.get("overrides", {})
    for name in sorted(set(old_ov) | set(new_ov)):
        if old_ov.get(name) != new_ov.get(name):
            lines.append(f"~ permissions changed: {name}")
    return lines


def write_config(data):
    """Write Apps/flatpaks.json; return True if it changed."""
    text = dump_config(data)
    try:
        if FLATPAK_JSON.read_text() == text:
            return False
    except OSError:
        pass
    FLATPAK_JSON.write_text(text)
    return True


def git_commit(paths, message):
    """Commit the given files in the config repo; returns a one-line result."""
    git = shutil.which("git")
    if not git:
        return "git not available; change left uncommitted"
    rel = [str(Path(p).relative_to(CONFIG_DIR)) for p in paths]
    subprocess.run([git, "add", "--"] + rel, cwd=CONFIG_DIR, check=False)
    staged = subprocess.run([git, "diff", "--cached", "--quiet", "--"] + rel, cwd=CONFIG_DIR, check=False)
    if staged.returncode == 0:
        return "nothing to commit"
    r = subprocess.run([git, "commit", "-q", "-m", message, "--"] + rel, cwd=CONFIG_DIR,
                       capture_output=True, text=True, check=False)
    if r.returncode != 0:
        return "commit failed: " + (r.stderr.strip() or r.stdout.strip())
    return f"committed: {message}"


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


# ---------------------------------------------------------------------------
# Steps: each is ("title", callable) or ("title", argv). Shared by CLI and GUI.


def root_cmd(action):
    """Run the privileged helper: sudo in a terminal, polkit otherwise."""
    if sys.stdin.isatty() and shutil.which("sudo"):
        return ["sudo", str(HELPER), action, str(CONFIG_DIR)]
    return ["pkexec", str(HELPER), action, str(CONFIG_DIR)]


def step_scan(log, dry_run=False):
    old = load_config()
    new, notes = scan_system(old)
    for n in notes:
        log(n)
    changes = diff_summary(old, new)
    if not changes:
        log("Flatpak list and permissions already match the config.")
        return False
    log("Flatpak changes found on this system:")
    for c in changes:
        log("  " + c)
    if dry_run:
        log(dump_config(new))
        return False
    write_config(new)
    log("Wrote " + str(FLATPAK_JSON))
    log(git_commit([FLATPAK_JSON], "Flatpaks: sync list and permissions from the system"))
    return True


def update_steps(scan=True):
    steps = []
    if scan:
        steps.append(("Scanning Flatpaks", lambda log: step_scan(log)))
    steps.append(("Refreshing flake inputs", ["nix", "flake", "update", "--flake", str(CONFIG_DIR)]))
    steps.append(("Committing flake.lock", lambda log: log(git_commit([CONFIG_DIR / "flake.lock"], "Update flake inputs"))))
    steps.append(("Building and switching to the new system", root_cmd("switch")))
    steps.append(("Updating Flatpaks", ["flatpak", "update", "--user", "-y", "--noninteractive"]))
    return steps


def flush_steps():
    return [
        ("Removing old home-manager and user generations", ["nix-collect-garbage", "-d"]),
        ("Removing unused Flatpak runtimes", ["flatpak", "uninstall", "--user", "--unused", "-y", "--noninteractive"]),
        ("Removing old system generations and boot entries", root_cmd("flush")),
    ]


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
    if args.command == "scan":
        step_scan(lambda line: print(line, flush=True), dry_run=args.dry_run)
        return 0
    if args.command == "update":
        rc = run_steps_cli(update_steps(scan=not args.no_scan))
        if rc == 0 and reboot_required():
            print("\n==> A reboot is needed for the new kernel to take effect.")
        return rc
    if args.command == "flush":
        return run_steps_cli(flush_steps())
    if args.command == "reboot":
        os.execvp("systemctl", ["systemctl", "reboot"])
    return 0


# ---------------------------------------------------------------------------
# GUI


def gui(smoke_test=False):
    from PyQt6.QtCore import QProcess, Qt, QTimer
    from PyQt6.QtGui import QFont, QFontDatabase, QIcon
    from PyQt6.QtWidgets import (QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMessageBox,
                                 QPlainTextEdit, QProgressBar, QPushButton, QSizePolicy, QToolButton,
                                 QVBoxLayout, QWidget)

    def icon(*names):
        for name in names:
            ic = QIcon.fromTheme(name)
            if not ic.isNull():
                return ic
        return QIcon()

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle(APP_NAME)
            self.setWindowIcon(icon(APP_ID, "system-software-update"))
            self.resize(960, 620)
            self.process = None
            self.queue = []
            self.current_title = ""

            root = QWidget()
            self.setCentralWidget(root)
            outer = QVBoxLayout(root)
            outer.setContentsMargins(16, 16, 16, 16)
            outer.setSpacing(12)

            # Header
            version, gen = system_info()
            title = QLabel(APP_NAME)
            f = title.font()
            f.setPointSize(f.pointSize() + 6)
            f.setBold(True)
            title.setFont(f)
            subtitle = QLabel(f"{version}  •  generation {gen}  •  {CONFIG_DIR}")
            subtitle.setStyleSheet("opacity: 0.7")
            outer.addWidget(title)
            outer.addWidget(subtitle)

            # Reboot banner
            self.banner = QFrame()
            self.banner.setFrameShape(QFrame.Shape.StyledPanel)
            bl = QHBoxLayout(self.banner)
            bl.addWidget(QLabel("A newer kernel is installed. Reboot to start using it."))
            bl.addStretch(1)
            reboot_now = QPushButton(icon("system-reboot"), "Reboot now")
            reboot_now.clicked.connect(self.reboot)
            bl.addWidget(reboot_now)
            self.banner.setVisible(reboot_required())
            outer.addWidget(self.banner)

            body = QHBoxLayout()
            body.setSpacing(12)
            outer.addLayout(body, 1)

            # Actions
            actions = QVBoxLayout()
            actions.setSpacing(8)
            self.buttons = []

            def add_action(text, icon_names, slot, tip):
                b = QToolButton()
                b.setText(text)
                b.setIcon(icon(*icon_names))
                b.setToolTip(tip)
                b.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextUnderIcon)
                b.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
                b.setMinimumSize(150, 88)
                b.setIconSize(b.iconSize() * 2)
                b.clicked.connect(slot)
                actions.addWidget(b)
                self.buttons.append(b)
                return b

            add_action("Update", ["system-software-update", "update-none"], self.update,
                       "Scan Flatpaks, refresh flake inputs, rebuild the system, update Flatpaks")
            add_action("Scan Flatpaks", ["flatpak-discover", "search", "system-search"], self.scan,
                       "Write the installed Flatpaks and their permissions into the config")
            add_action("Flush", ["edit-clear-history", "user-trash"], self.flush,
                       "Remove old generations, boot entries and unused Flatpak runtimes")
            add_action("Reboot", ["system-reboot"], self.reboot, "Reboot the machine")
            actions.addStretch(1)
            body.addLayout(actions)

            # Log
            right = QVBoxLayout()
            self.log_view = QPlainTextEdit()
            self.log_view.setReadOnly(True)
            self.log_view.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            self.log_view.setMaximumBlockCount(5000)
            right.addWidget(self.log_view, 1)
            self.progress = QProgressBar()
            self.progress.setRange(0, 0)
            self.progress.setVisible(False)
            right.addWidget(self.progress)
            body.addLayout(right, 1)

            self.statusBar().showMessage("Ready")
            self.log(f"Config: {CONFIG_DIR}")
            self.log("Pick an action on the left. Output appears here.")

        # -- helpers
        def log(self, text):
            self.log_view.appendPlainText(text.rstrip("\n"))

        def set_busy(self, busy, message=""):
            for b in self.buttons:
                b.setEnabled(not busy)
            self.progress.setVisible(busy)
            self.statusBar().showMessage(message or ("Working…" if busy else "Ready"))

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
            self.statusBar().showMessage(title)
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
            self.banner.setVisible(reboot_required())
            if code == 0:
                self.log("\n" + self.done_message)
                if self.banner.isVisible():
                    self.log("A reboot is needed for the new kernel to take effect.")
            else:
                self.log("\nStopped. Fix the problem above and try again.")

        # -- actions
        def update(self):
            self.run(update_steps(), "System update finished.")

        def scan(self):
            self.run([("Scanning Flatpaks", lambda log: step_scan(log))], "Flatpak scan finished.")

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
        QTimer.singleShot(200, app.quit)
    return app.exec()


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(prog=APP_ID, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("gui", help="open the window (default)").add_argument("--smoke-test", action="store_true", help=argparse.SUPPRESS)
    up = sub.add_parser("update", help="scan flatpaks, refresh inputs, rebuild, update flatpaks")
    up.add_argument("--no-scan", action="store_true", help="skip the flatpak scan")
    sc = sub.add_parser("scan", help="write the installed flatpaks and permissions into the config")
    sc.add_argument("--dry-run", action="store_true", help="only show what would change")
    sub.add_parser("flush", help="remove old generations and unused flatpaks")
    sub.add_parser("reboot", help="reboot")
    args = parser.parse_args()
    if args.command in (None, "gui"):
        return gui(smoke_test=getattr(args, "smoke_test", False))
    return cli(args)


if __name__ == "__main__":
    sys.exit(main())
