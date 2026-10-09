#!/usr/bin/env python3
"""NixOS Updater: update this machine from its flake and keep the parts of the
config that describe this machine (Flatpaks, autostart, shortcuts, service
toggles, unattended updates) in sync, committing every change to the repo.

GUI by default (Qt, follows the Plasma style). Subcommands for the terminal:

    nixos-updater update [--no-sync]   sync, refresh inputs, rebuild, update flatpaks
    nixos-updater sync [--dry-run]     import flatpaks and autostart entries into the config
    nixos-updater apply                rebuild from the config as it is now
    nixos-updater flush                remove old generations and unused flatpaks
    nixos-updater push                 git push the config repo
    nixos-updater reboot
"""

import argparse
import configparser
import json
import os
import re
import shutil
import subprocess
import sys
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
    "services": CONFIG_DIR / "Config" / "services.json",
    "autoupdate": CONFIG_DIR / "Config" / "autoupdate.json",
}
DEFAULTS = {
    "flatpaks": {"packages": [], "overrides": {}},
    "autostart": [],
    "shortcuts": [],
    "services": {},
    "autoupdate": {"enabled": False, "schedule": "Sun 04:00", "mode": "boot", "reboot": False, "flatpaks": True},
}

# Keys under [Context] in a flatpak override file hold ';'-separated lists.
LIST_KEYS = {"shared", "sockets", "devices", "features", "filesystems", "persistent"}
SCHEDULES = [
    ("Daily at 04:00", "*-*-* 04:00"),
    ("Weekly, Sunday 04:00", "Sun 04:00"),
    ("Monthly, the 1st at 04:00", "*-*-01 04:00"),
]


# ---------------------------------------------------------------------------
# Config files


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


def save_and_commit(name, data, message, log):
    if save_json(name, data):
        log(f"Wrote {FILES[name]}")
        log(git_commit([FILES[name]], message))
        return True
    log("No changes.")
    return False


def run_capture(argv, cwd=None):
    """Run a command and return its stdout, or "" if it fails."""
    try:
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return ""


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
    return [("Pushing the config repo", ["git", "push"])]


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
        return run_steps_cli(push_steps())
    if args.command == "reboot":
        os.execvp("systemctl", ["systemctl", "reboot"])
    return 0


# ---------------------------------------------------------------------------
# GUI


def gui(smoke_test=False):
    from PyQt6.QtCore import QProcess, Qt, QTimer
    from PyQt6.QtGui import QFontDatabase, QIcon, QKeySequence
    from PyQt6.QtWidgets import (QAbstractItemView, QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox,
                                 QFormLayout, QFrame, QGroupBox, QHBoxLayout, QKeySequenceEdit, QLabel, QLineEdit,
                                 QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QPlainTextEdit, QProgressBar,
                                 QPushButton, QSizePolicy, QTableWidget, QTableWidgetItem, QTabWidget, QToolButton,
                                 QVBoxLayout, QWidget)

    def icon(*names):
        for name in names:
            ic = QIcon.fromTheme(name)
            if not ic.isNull():
                return ic
        return QIcon()

    def hint(text):
        label = QLabel(text)
        label.setWordWrap(True)
        label.setStyleSheet("opacity: 0.75")
        return label

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
            self.apps = available_apps()
            for app in self.apps:
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
            self.resize(420, 0)
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

    # -- editor tabs

    class AutostartTab(QWidget):
        def __init__(self, window):
            super().__init__()
            self.window = window
            self.entries = load_json("autostart")
            layout = QVBoxLayout(self)
            layout.addWidget(hint("Applications and commands started with your Plasma session. "
                                  "Entries you add in Plasma's own Autostart settings are imported on the next sync."))
            self.list = QListWidget()
            self.list.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
            layout.addWidget(self.list, 1)
            row = QHBoxLayout()
            add_app = QPushButton(icon("list-add"), "Add application…")
            add_app.clicked.connect(self.add_app)
            add_cmd = QPushButton(icon("utilities-terminal"), "Add command…")
            add_cmd.clicked.connect(self.add_cmd)
            remove = QPushButton(icon("list-remove"), "Remove")
            remove.clicked.connect(self.remove)
            row.addWidget(add_app)
            row.addWidget(add_cmd)
            row.addWidget(remove)
            row.addStretch(1)
            save = QPushButton(icon("document-save"), "Save")
            save.clicked.connect(self.save)
            row.addWidget(save)
            layout.addLayout(row)
            self.refresh()

        def refresh(self):
            self.list.clear()
            for e in self.entries:
                item = QListWidgetItem(icon(e.get("icon", ""), "application-x-executable"), f'{e["name"]}  —  {e["exec"]}')
                self.list.addItem(item)

        def add_entry(self, entry):
            self.entries = [e for e in self.entries if e["file"] != entry["file"]] + [entry]
            self.entries.sort(key=lambda e: e["name"].lower())
            self.refresh()

        def add_app(self):
            dialog = PickAppDialog(self)
            if dialog.exec() and dialog.chosen():
                self.add_entry(dialog.chosen())

        def add_cmd(self):
            dialog = CommandDialog(self, "Add command to autostart", with_shortcut=False)
            if dialog.exec() and dialog.name.text().strip() and dialog.command.text().strip():
                name = dialog.name.text().strip()
                slug = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-").lower() or "command"
                self.add_entry({"file": f"{slug}.desktop", "name": name, "exec": dialog.command.text().strip(), "icon": "utilities-terminal"})

        def remove(self):
            rows = sorted({i.row() for i in self.list.selectedIndexes()}, reverse=True)
            for r in rows:
                del self.entries[r]
            self.refresh()

        def save(self):
            self.window.log("\n==> Saving autostart entries")
            if save_and_commit("autostart", self.entries, "Autostart: update entries", self.window.log):
                self.window.needs_apply()

    class ShortcutsTab(QWidget):
        def __init__(self, window):
            super().__init__()
            self.window = window
            self.entries = load_json("shortcuts")
            layout = QVBoxLayout(self)
            layout.addWidget(hint("Global shortcuts that run a command. Applied through plasma-manager on the next rebuild; "
                                  "they take effect after logging in again."))
            self.table = QTableWidget(0, 3)
            self.table.setHorizontalHeaderLabels(["Name", "Shortcut", "Command"])
            self.table.horizontalHeader().setStretchLastSection(True)
            self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            layout.addWidget(self.table, 1)
            row = QHBoxLayout()
            add = QPushButton(icon("list-add"), "Add shortcut…")
            add.clicked.connect(self.add)
            remove = QPushButton(icon("list-remove"), "Remove")
            remove.clicked.connect(self.remove)
            row.addWidget(add)
            row.addWidget(remove)
            row.addStretch(1)
            save = QPushButton(icon("document-save"), "Save")
            save.clicked.connect(self.save)
            row.addWidget(save)
            layout.addLayout(row)
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
            dialog = CommandDialog(self, "Add shortcut", with_shortcut=True)
            if not dialog.exec():
                return
            name, command = dialog.name.text().strip(), dialog.command.text().strip()
            key = dialog.key.keySequence().toString(QKeySequence.SequenceFormat.PortableText)
            if not (name and command and key):
                QMessageBox.warning(self, "Add shortcut", "Name, shortcut and command are all needed.")
                return
            self.entries = [e for e in self.entries if e["name"].lower() != name.lower()]
            self.entries.append({"name": name, "key": key, "command": command})
            self.entries.sort(key=lambda e: e["name"].lower())
            self.refresh()

        def remove(self):
            rows = sorted({i.row() for i in self.table.selectedIndexes()}, reverse=True)
            for r in rows:
                del self.entries[r]
            self.refresh()

        def save(self):
            self.window.log("\n==> Saving shortcuts")
            if save_and_commit("shortcuts", self.entries, "Shortcuts: update custom command shortcuts", self.window.log):
                self.window.needs_apply()

    class ServicesTab(QWidget):
        def __init__(self, window):
            super().__init__()
            self.window = window
            self.data = load_json("services")
            layout = QVBoxLayout(self)
            layout.addWidget(hint("System services this config knows how to set up. Tick what you want, save, then Apply."))
            self.boxes = {}
            for name in sorted(self.data):
                box = QCheckBox(f'{name}  —  {self.data[name].get("description", "")}')
                box.setChecked(bool(self.data[name].get("enabled")))
                self.boxes[name] = box
                layout.addWidget(box)
            layout.addStretch(1)
            row = QHBoxLayout()
            row.addStretch(1)
            save = QPushButton(icon("document-save"), "Save")
            save.clicked.connect(self.save)
            row.addWidget(save)
            layout.addLayout(row)

        def save(self):
            for name, box in self.boxes.items():
                self.data[name]["enabled"] = box.isChecked()
            self.window.log("\n==> Saving service toggles")
            if save_and_commit("services", self.data, "Services: update toggles", self.window.log):
                self.window.needs_apply()

    class AutoUpdateTab(QWidget):
        def __init__(self, window):
            super().__init__()
            self.window = window
            self.data = load_json("autoupdate")
            layout = QVBoxLayout(self)
            layout.addWidget(hint("Unattended updates run by a systemd timer as root: refresh flake inputs, rebuild, "
                                  "update Flatpaks. Missed runs happen at the next boot."))
            box = QGroupBox("Schedule")
            form = QFormLayout(box)
            self.enabled = QCheckBox("Enable automatic updates")
            self.enabled.setChecked(bool(self.data.get("enabled")))
            form.addRow(self.enabled)
            self.schedule = QComboBox()
            for label, _ in SCHEDULES:
                self.schedule.addItem(label)
            self.schedule.addItem("Custom (systemd OnCalendar)")
            self.custom = QLineEdit()
            self.custom.setPlaceholderText("e.g. Mon,Fri 03:30")
            current = self.data.get("schedule", "Sun 04:00")
            presets = [s for _, s in SCHEDULES]
            if current in presets:
                self.schedule.setCurrentIndex(presets.index(current))
            else:
                self.schedule.setCurrentIndex(len(presets))
                self.custom.setText(current)
            self.schedule.currentIndexChanged.connect(self.toggle_custom)
            form.addRow("When", self.schedule)
            form.addRow("Custom", self.custom)
            self.toggle_custom()
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
            layout.addWidget(box)
            layout.addStretch(1)
            row = QHBoxLayout()
            row.addStretch(1)
            save = QPushButton(icon("document-save"), "Save")
            save.clicked.connect(self.save)
            row.addWidget(save)
            layout.addLayout(row)

        def toggle_custom(self):
            self.custom.setEnabled(self.schedule.currentIndex() == len(SCHEDULES))

        def save(self):
            idx = self.schedule.currentIndex()
            schedule = SCHEDULES[idx][1] if idx < len(SCHEDULES) else self.custom.text().strip()
            if not schedule:
                QMessageBox.warning(self, "Auto updates", "Enter a schedule.")
                return
            self.data = {
                "enabled": self.enabled.isChecked(),
                "schedule": schedule,
                "mode": self.mode.currentData(),
                "reboot": self.reboot.isChecked(),
                "flatpaks": self.flatpaks.isChecked(),
            }
            self.window.log("\n==> Saving auto update settings")
            if save_and_commit("autoupdate", self.data, "Auto updates: change schedule", self.window.log):
                self.window.needs_apply()

    # -- main window

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle(APP_NAME)
            self.setWindowIcon(icon(APP_ID, "system-software-update"))
            self.resize(1040, 720)
            self.process = None
            self.queue = []
            self.current_title = ""
            self.done_message = ""

            root = QWidget()
            self.setCentralWidget(root)
            outer = QVBoxLayout(root)
            outer.setContentsMargins(16, 16, 16, 16)
            outer.setSpacing(10)

            version, gen = system_info()
            title = QLabel(APP_NAME)
            f = title.font()
            f.setPointSize(f.pointSize() + 6)
            f.setBold(True)
            title.setFont(f)
            outer.addWidget(title)
            outer.addWidget(hint(f"{version}  •  generation {gen}  •  {CONFIG_DIR}"))

            self.banner = QFrame()
            self.banner.setFrameShape(QFrame.Shape.StyledPanel)
            bl = QHBoxLayout(self.banner)
            self.banner_text = QLabel()
            bl.addWidget(self.banner_text, 1)
            self.banner_button = QPushButton()
            bl.addWidget(self.banner_button)
            self.banner.setVisible(False)
            outer.addWidget(self.banner)

            self.tabs = QTabWidget()
            self.tabs.addTab(self.system_tab(), icon("system-software-update"), "System")
            self.tabs.addTab(AutostartTab(self), icon("preferences-desktop-startup", "system-run"), "Autostart")
            self.tabs.addTab(ShortcutsTab(self), icon("preferences-desktop-keyboard", "input-keyboard"), "Shortcuts")
            self.tabs.addTab(ServicesTab(self), icon("preferences-system-services", "system-run"), "Services")
            self.tabs.addTab(AutoUpdateTab(self), icon("chronometer", "appointment-new"), "Auto Updates")
            outer.addWidget(self.tabs, 1)

            self.log_view = QPlainTextEdit()
            self.log_view.setReadOnly(True)
            self.log_view.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            self.log_view.setMaximumBlockCount(5000)
            self.log_view.setMinimumHeight(180)
            outer.addWidget(self.log_view, 1)
            self.progress = QProgressBar()
            self.progress.setRange(0, 0)
            self.progress.setVisible(False)
            outer.addWidget(self.progress)

            self.statusBar().showMessage("Ready")
            self.log(f"Config: {CONFIG_DIR}")
            self.log("Pick an action. Output appears here.")
            self.refresh_banner()

        def system_tab(self):
            tab = QWidget()
            layout = QHBoxLayout(tab)
            self.buttons = []

            def add_action(text, icon_names, slot, tip):
                b = QToolButton()
                b.setText(text)
                b.setIcon(icon(*icon_names))
                b.setToolTip(tip)
                b.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextUnderIcon)
                b.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
                b.setMinimumSize(140, 84)
                b.setIconSize(b.iconSize() * 2)
                b.clicked.connect(slot)
                layout.addWidget(b)
                self.buttons.append(b)

            add_action("Update", ["system-software-update", "update-none"], self.update,
                       "Sync Flatpaks and autostart, refresh flake inputs, rebuild, update Flatpaks")
            add_action("Apply", ["dialog-ok-apply", "system-run"], self.apply,
                       "Rebuild from the config as it is now (after saving changes in the tabs)")
            add_action("Sync", ["flatpak-discover", "view-refresh"], self.sync,
                       "Import installed Flatpaks, their permissions and autostart entries into the config")
            add_action("Push", ["vcs-push", "cloud-upload", "go-up"], self.push, "git push the config repo")
            add_action("Flush", ["edit-clear-history", "user-trash"], self.flush,
                       "Remove old generations, boot entries and unused Flatpak runtimes")
            add_action("Reboot", ["system-reboot"], self.reboot, "Reboot the machine")
            return tab

        # -- helpers
        def log(self, text):
            self.log_view.appendPlainText(text.rstrip("\n"))

        def set_busy(self, busy, message=""):
            for b in self.buttons:
                b.setEnabled(not busy)
            self.progress.setVisible(busy)
            self.statusBar().showMessage(message or ("Working…" if busy else "Ready"))

        def refresh_banner(self):
            if reboot_required():
                self.show_banner("A newer kernel is installed. Reboot to start using it.", "Reboot now", self.reboot)
            else:
                self.banner.setVisible(False)

        def show_banner(self, text, button, slot):
            self.banner_text.setText(text)
            self.banner_button.setText(button)
            try:
                self.banner_button.clicked.disconnect()
            except TypeError:
                pass
            self.banner_button.clicked.connect(slot)
            self.banner.setVisible(True)

        def needs_apply(self):
            self.log("Saved and committed. Click Apply (or Update) to activate it.")
            if not reboot_required():
                self.show_banner("Changes saved to the config. Rebuild to activate them.", "Apply now", self.apply)

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
            self.run(push_steps(), "Push finished.")

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
        QTimer.singleShot(0, lambda: [win.tabs.setCurrentIndex(i) for i in range(win.tabs.count())])
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
    args = parser.parse_args()
    if args.command in (None, "gui"):
        return gui(smoke_test=getattr(args, "smoke_test", False))
    return cli(args)


if __name__ == "__main__":
    sys.exit(main())
