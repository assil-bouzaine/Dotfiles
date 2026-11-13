#!/usr/bin/env python3
"""Task manager window (click ram in the bar, SUPER + T; again to close).

A small floating window listing the apps by memory or CPU use, refreshed
every two seconds. All processes of one app are added up (a browser is one
row, not forty), with the app's own name and icon where it has a .desktop
entry. The x on a row ends the app: one click arms it, a second confirms;
if the app ignores the request, the button turns into "Force end".

Memory per process is PSS (/proc/<pid>/smaps_rollup): shared pages are split
between the processes sharing them, so the rows add up to real usage. CPU
is the share of all cores since the last refresh.

Reading PSS is slow-ish, so sampling runs in a worker thread and memory is
re-read every other tick. Look: tasks.css, same tokens as the bar.
Hyprland floats it by its class, bar-tasks (hypr/conf.d/rules.lua).
"""

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import warnings

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.realpath(__file__))
TICK = 2.0            # seconds between refreshes
MEMORY_EVERY = 2      # re-read memory every n-th tick
ARMED_FOR = 3.0       # seconds the "End task" confirmation stays up
GRACE = 3.0           # seconds an app gets to quit before "Force end"

# Run through an interpreter: named after the script, not "python3"
INTERPRETERS = re.compile(r"^(python[\d.]*|node|bash|sh|lua[\d.]*|perl|ruby|electron\d*|bun|deno)$")
# Ending these ends the session or breaks sound / the desktop: no x
SYSTEM = {"Hyprland", "systemd", "dbus-daemon", "dbus-broker", "pipewire", "pipewire-pulse",
          "wireplumber", "Xwayland", "waybar", "ly-dm", "xdg-desktop-portal",
          "xdg-desktop-portal-hyprland", "xdg-desktop-portal-gtk", "tasks.py"}


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode(errors="replace")
    except OSError:
        return ""


def size(kb):
    mb = kb / 1024
    return f"{mb / 1024:.1f} GB" if mb >= 1000 else f"{mb:.0f} MB"


# ── Sampling (worker thread) ─────────────────────────────────────────────

def app_key(pid):
    """What a process is called in the list: its program, or its script."""
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).removesuffix(" (deleted)")
    except OSError:
        return None  # kernel thread, or someone else's process
    if re.fullmatch(r"[\d.]+", exe):  # binary named after its version (claude)
        exe = read(f"/proc/{pid}/comm").strip() or exe
    if INTERPRETERS.match(exe):
        args = read(f"/proc/{pid}/cmdline").split("\0")[1:]
        if args[:1] == ["-m"] and len(args) > 1:
            return args[1]
        script = next((a for a in args if a and not a.startswith("-")), None)
        if script and args[:1] != ["-c"]:
            return os.path.basename(script)
    return exe


def memory_kb(pid):
    m = re.search(r"^Pss:\s+(\d+)", read(f"/proc/{pid}/smaps_rollup"), re.M)
    if m:
        return int(m.group(1))
    m = re.search(r"^VmRSS:\s+(\d+)", read(f"/proc/{pid}/status"), re.M)
    return int(m.group(1)) if m else 0


def cpu_ticks(pid):
    """(start time, cpu ticks used so far) of a process, or None."""
    stat = read(f"/proc/{pid}/stat")
    fields = stat[stat.rfind(")") + 2:].split()
    try:
        return int(fields[19]), int(fields[11]) + int(fields[12])
    except (IndexError, ValueError):
        return None


def all_cpu_ticks():
    """(total, idle) ticks of all cores together."""
    v = [int(x) for x in read("/proc/stat").split("\n", 1)[0].split()[1:]]
    return sum(v[:8]), v[3] + v[4]


def desktop_entries():
    """Lookup of .desktop entries by id, window class and program name."""
    index = {}
    for app in Gio.AppInfo.get_all():
        keys = [(app.get_id() or "").removesuffix(".desktop"),
                app.get_startup_wm_class() or "",
                os.path.basename(app.get_executable() or "")]
        for k in keys:
            if k:
                index.setdefault(k.lower(), app)
    return index


def window_classes():
    """pid -> window class of the apps that have a window open."""
    try:
        out = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True,
                             text=True, timeout=2).stdout
        return {c["pid"]: c["class"] for c in json.loads(out) if c.get("class")}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


class Sampler:
    """Adds the processes up per app. sample() returns (apps, totals)."""

    def __init__(self):
        self.entries = desktop_entries()
        self.procs = {}       # pid -> {start, key, ticks, kb}
        self.total = all_cpu_ticks()
        self.tick = 0

    def sample(self):
        mine = os.getuid()
        total = all_cpu_ticks()
        span = max(total[0] - self.total[0], 1)
        busy = span - (total[1] - self.total[1])
        read_memory = self.tick % MEMORY_EVERY == 0
        self.tick += 1

        procs, groups = {}, {}
        for pid in filter(str.isdigit, os.listdir("/proc")):
            try:
                if os.stat(f"/proc/{pid}").st_uid != mine:
                    continue
            except OSError:
                continue
            now = cpu_ticks(pid)
            if not now:
                continue
            old = self.procs.get(pid)
            if old and old["start"] == now[0]:
                p = dict(old, used=now[1] - old["ticks"], ticks=now[1])
                if read_memory:
                    p["kb"] = memory_kb(pid)
            else:
                key = app_key(pid)
                if not key:
                    continue
                p = {"start": now[0], "key": key, "ticks": now[1], "used": 0, "kb": memory_kb(pid)}
            procs[pid] = p
            g = groups.setdefault(p["key"], {"key": p["key"], "kb": 0, "ticks": 0, "pids": []})
            g["kb"] += p["kb"]
            g["ticks"] += p["used"]
            g["pids"].append(int(pid))
        self.procs, self.total = procs, total

        classes = window_classes()
        for g in groups.values():
            cls = next((classes[p] for p in g["pids"] if p in classes), None)
            entry = self.entries.get((cls or "").lower()) or self.entries.get(g["key"].lower())
            g["name"] = entry.get_name() if entry else g["key"]
            g["icon"] = entry.get_icon() if entry else None
            g["cpu"] = 100 * g["ticks"] / span
        info = dict(re.findall(r"^(\w+):\s+(\d+)", read("/proc/meminfo"), re.M))
        mem_total = int(info["MemTotal"])
        totals = {"mem_total": mem_total, "mem_used": mem_total - int(info["MemAvailable"]),
                  "cpu": 100 * busy / span}
        return [g for g in groups.values() if g["kb"] > 0], totals


# ── Window ───────────────────────────────────────────────────────────────

class Row(Gtk.ListBoxRow):
    def __init__(self, app, on_end):
        super().__init__(selectable=False, activatable=False)
        self.app = app
        self.state = "idle"      # idle → armed → closing → stuck
        self.since = 0.0

        box = Gtk.Box(spacing=12)
        self.add(box)
        self.icon = Gtk.Image(pixel_size=22)
        self.icon.set_size_request(22, 22)
        self.name = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, hexpand=True)
        self.cpu = Gtk.Label(xalign=1, width_chars=5)
        self.cpu.get_style_context().add_class("num")
        self.bar = Gtk.ProgressBar(valign=Gtk.Align.CENTER)
        self.bar.set_size_request(84, -1)
        self.mem = Gtk.Label(xalign=1, width_chars=7)
        self.mem.get_style_context().add_class("num")
        self.end = Gtk.Button(valign=Gtk.Align.CENTER, halign=Gtk.Align.END, relief=Gtk.ReliefStyle.NONE)
        self.end.get_style_context().add_class("end")
        self.end.connect("clicked", lambda _b: on_end(self))
        slot = Gtk.Box()          # keeps the columns aligned on rows without an x
        slot.set_size_request(84, -1)
        slot.pack_end(self.end, False, False, 0)
        for w in (self.icon, self.name, self.cpu, self.bar, self.mem, slot):
            box.pack_start(w, w is self.name, True, 0)
        if app["key"] in SYSTEM:
            self.end.set_no_show_all(True)
            self.end.hide()
        self.set_state("idle")

    def set_state(self, state):
        self.state, self.since = state, time.monotonic()
        ctx = self.end.get_style_context()
        label, tip, danger = {
            "idle":    ("󰅖", "End this app", False),
            "armed":   ("End task", "Click again to end it", True),
            "closing": ("Ending…", "", False),
            "stuck":   ("Force end", "It didn't quit when asked. This ends it now; unsaved work is lost.", True),
        }[state]
        self.end.set_label(label)
        self.end.set_tooltip_text(tip or None)
        self.end.set_sensitive(state != "closing")
        (ctx.add_class if danger else ctx.remove_class)("danger")

    def update(self, app, biggest, mem_total):
        self.app = app
        self.name.set_text(app["name"])
        if app["icon"]:
            self.icon.set_from_gicon(app["icon"], Gtk.IconSize.LARGE_TOOLBAR)
        cpu = app["cpu"]
        self.cpu.set_text(f"{cpu:.0f}%" if cpu >= 0.5 else "0%")
        self.mem.set_text(size(app["kb"]))
        self.bar.set_fraction(min(app["kb"] / biggest, 1))
        share = app["kb"] / mem_total
        for cls, on in (("idle", cpu < 0.5), ("warn", cpu >= 50)):
            (self.cpu.get_style_context().add_class if on else self.cpu.get_style_context().remove_class)(cls)
        for cls, on in (("warn", 0.2 <= share < 0.4), ("crit", share >= 0.4)):
            (self.bar.get_style_context().add_class if on else self.bar.get_style_context().remove_class)(cls)


class Window(Gtk.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application, title="Task manager")
        self.set_default_size(580, 620)
        self.rows = {}
        self.sort_by = "kb"
        self.sampler = Sampler()
        self.alive = True

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.get_style_context().add_class("root")
        self.add(root)

        # totals: memory and CPU, each a figure over a thin line like the bar's
        totals = Gtk.Box(spacing=14, homogeneous=True)
        self.mem_total, self.mem_line = self.total_block(totals, "Memory")
        self.cpu_total, self.cpu_line = self.total_block(totals, "CPU")
        root.pack_start(totals, False, False, 0)

        self.search = Gtk.Entry(placeholder_text="Search apps")
        self.search.connect("changed", lambda _e: self.list.invalidate_filter())
        root.pack_start(self.search, False, False, 0)

        # column heads: click CPU or Memory to sort by it
        heads = Gtk.Box(spacing=12)
        heads.get_style_context().add_class("heads")
        app_head = Gtk.Label(label="App", xalign=0, hexpand=True)
        self.cpu_head = self.sort_button("CPU", "cpu", 5)
        self.mem_head = self.sort_button("Memory", "kb", 7)
        mem_slot = Gtk.Box()
        mem_slot.set_size_request(84 + 12, -1)
        gap = Gtk.Box()
        gap.set_size_request(84, -1)
        heads.pack_start(app_head, True, True, 0)
        heads.pack_start(self.cpu_head, False, False, 0)
        heads.pack_start(mem_slot, False, False, 0)
        heads.pack_start(self.mem_head, False, False, 0)
        heads.pack_start(gap, False, False, 0)
        root.pack_start(heads, False, False, 0)

        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.set_sort_func(lambda a, b: (b.app[self.sort_by] > a.app[self.sort_by]) - (b.app[self.sort_by] < a.app[self.sort_by]))
        self.list.set_filter_func(lambda r: self.search.get_text().lower() in r.app["name"].lower())
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.list)
        root.pack_start(scroll, True, True, 0)

        hint = Gtk.Label(label="The x ends an app: click it, then confirm. Esc closes this window.", xalign=0)
        hint.get_style_context().add_class("hint")
        root.pack_start(hint, False, False, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", self.on_destroy)
        self.mark_sort()
        threading.Thread(target=self.work, daemon=True).start()

    def total_block(self, parent, title):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
        box.get_style_context().add_class("total")
        line = Gtk.Box(spacing=8)
        name = Gtk.Label(label=title, xalign=0)
        name.get_style_context().add_class("muted")
        value = Gtk.Label(xalign=0, hexpand=True)
        value.get_style_context().add_class("num")
        line.pack_start(name, False, False, 0)
        line.pack_start(value, True, True, 0)
        bar = Gtk.ProgressBar()
        box.pack_start(line, False, False, 0)
        box.pack_start(bar, False, False, 0)
        parent.pack_start(box, True, True, 0)
        return value, bar

    def sort_button(self, text, field, chars):
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=f"Sort by {text}")
        label = Gtk.Label(label=text, xalign=1, width_chars=chars)
        button.add(label)
        button.connect("clicked", lambda _b: self.set_sort(field))
        return button

    def set_sort(self, field):
        self.sort_by = field
        self.mark_sort()
        self.list.invalidate_sort()

    def mark_sort(self):
        for button, field in ((self.cpu_head, "cpu"), (self.mem_head, "kb")):
            ctx = button.get_style_context()
            (ctx.add_class if field == self.sort_by else ctx.remove_class)("sorted")

    def on_key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        if not self.search.is_focus():
            self.search.grab_focus_without_selecting()
        return False

    def on_destroy(self, _w):
        self.alive = False

    # sampling thread → main loop
    def work(self):
        while self.alive:
            started = time.monotonic()
            try:
                result = self.sampler.sample()
            except Exception:  # a process vanishing mid-read must not end the window
                result = None
            if result:
                GLib.idle_add(self.show_sample, *result)
            first = self.sampler.tick == 1  # CPU needs two readings: come back sooner
            time.sleep(max(0.2, (0.6 if first else TICK) - (time.monotonic() - started)))

    def show_sample(self, apps, totals):
        if not self.alive:
            return False
        used, total = totals["mem_used"], totals["mem_total"]
        self.mem_total.set_text(f"{size(used)} of {size(total)}")
        self.mem_line.set_fraction(used / total)
        self.cpu_total.set_text(f"{totals['cpu']:.0f}%")
        self.cpu_line.set_fraction(min(totals["cpu"] / 100, 1))
        for line, value, warn, crit in ((self.mem_line, used / total, 0.75, 0.9),
                                        (self.cpu_line, totals["cpu"] / 100, 0.7, 0.9)):
            ctx = line.get_style_context()
            (ctx.add_class if warn <= value < crit else ctx.remove_class)("warn")
            (ctx.add_class if value >= crit else ctx.remove_class)("crit")

        biggest = max((a["kb"] for a in apps), default=1)
        now = time.monotonic()
        seen = set()
        for app in apps:
            seen.add(app["key"])
            row = self.rows.get(app["key"])
            if not row:
                row = self.rows[app["key"]] = Row(app, self.on_end)
                self.list.add(row)
                row.show_all()
            row.update(app, biggest, total)
            if row.state == "armed" and now - row.since > ARMED_FOR:
                row.set_state("idle")
            elif row.state == "closing" and now - row.since > GRACE:
                row.set_state("stuck")
        for key in [k for k in self.rows if k not in seen]:
            self.list.remove(self.rows.pop(key))
        # rows don't jump around under the pointer or an armed button
        if not self.pointer_over_list() and all(r.state == "idle" for r in self.rows.values()):
            self.list.invalidate_sort()
        return False

    def pointer_over_list(self):
        win = self.list.get_window()
        if not win:
            return False
        pointer = self.get_display().get_default_seat().get_pointer()
        _w, x, y, _m = win.get_device_position(pointer)
        return 0 <= x < win.get_width() and 0 <= y < win.get_height()

    def on_end(self, row):
        if row.state == "idle":
            row.set_state("armed")
            GLib.timeout_add(int(ARMED_FOR * 1000) + 50,
                             lambda: row.state == "armed" and row.set_state("idle") and False)
            return
        sig = signal.SIGKILL if row.state == "stuck" else signal.SIGTERM
        for pid in row.app["pids"]:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
        row.set_state("closing")


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="bar.tasks")
        self.window = None

    def do_activate(self):
        if self.window:           # launched again: the shortcut toggles it
            self.window.close()
            return
        css = Gtk.CssProvider()
        css.load_from_path(f"{HERE}/tasks.css")
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        self.window = Window(self)
        self.window.show_all()
        self.window.set_focus(None)  # placeholder stays readable; typing still lands in the search


if __name__ == "__main__":
    GLib.set_prgname("bar-tasks")  # the window class Hyprland matches
    sys.exit(App().run([]))
