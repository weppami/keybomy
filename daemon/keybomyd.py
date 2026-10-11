#!/usr/bin/env python3
"""keybomyd: counts key presses, never what you type.

A Linux port of the counting half of Shakespeare (github.com/andreasaez/shakespeare).
It reads key-down events from every keyboard under /dev/input, reduces each one at
once to a coarse class (letter, space, other, ignored) and keeps only per-day
counters. Key codes are never stored, and neither is their order.

Files, in the data directory (default ~/.local/share/keybomy, created 0700):
  stats.json   every day's counters, same schema as Shakespeare's stats.json
  live.json    today's counters plus daemon status, rewritten every couple of
               seconds while you type so the bar stays current
  reset        created by the panel to ask for "Delete all data"

Standard library only. Needs read access to /dev/input/event*; the systemd unit
grants that to this process alone via SupplementaryGroups=input.
"""

import collections
import ctypes
import errno
import fcntl
import json
import os
import select
import signal
import struct
import sys
import time

VERSION = "0.1.0"

# struct input_event on 64-bit Linux: struct timeval (two longs), u16 type, u16 code, s32 value.
EVENT = struct.Struct("llHHi")
EV_KEY = 0x01

KEY_SPACE = 57
KEY_Q, KEY_W = 16, 17
LETTERS = set(range(16, 26)) | set(range(30, 39)) | set(range(44, 51))  # QWERTY rows, by position
SHIFT = {42, 54}
CTRL = {29, 97}
LEFT_ALT = 56
RIGHT_ALT = 100  # AltGr types characters on most layouts, so it is not a shortcut modifier
SUPER = {125, 126}
CAPS_LOCK = 58
MODIFIERS = SHIFT | CTRL | SUPER | {LEFT_ALT, RIGHT_ALT, CAPS_LOCK}
FIRST_BUTTON = 0x100  # BTN_MISC: mouse and joystick buttons start here

STREAK_THRESHOLD = 50
KEYS_PER_WORD = 5.0
WPM_WINDOW = 60.0
MAX_STAMPS = 6000
MAX_WPM = 400.0
MAX_COUNT = 1_000_000_000
MAX_DAYS = 20_000
MAX_FILE_BYTES = 10_000_000

SAVE_EVERY = 60.0   # stats.json
LIVE_EVERY = 2.0    # live.json while typing
HEARTBEAT = 60.0    # live.json when idle, so the panel knows the daemon is alive
RESCAN_EVERY = 5.0  # pick up keyboards plugged in later


def log(message):
    print(message, file=sys.stderr, flush=True)


def make_undumpable():
    """Keep other processes of the same user from reading our input devices
    through /proc/<pid>/fd or ptrace: only this process holds the input group."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        PR_SET_DUMPABLE = 4
        if libc.prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0:
            log("keybomyd: prctl(PR_SET_DUMPABLE) failed")
    except OSError:
        log("keybomyd: could not load libc for prctl")


# ---------------------------------------------------------------- classification

def classify(code, held):
    """letter, space, other or ignored. Mirrors Shakespeare's KeyClassifier:
    Ctrl, Alt or Super turn a press into a shortcut; Super+Q and Super+W close
    windows in Omarchy, which is housekeeping rather than typing."""
    has_super = bool(held & SUPER)
    if has_super and code in (KEY_Q, KEY_W):
        return "ignored"
    if has_super or held & CTRL or LEFT_ALT in held:
        return "other"
    if code == KEY_SPACE:
        return "space"
    return "letter" if code in LETTERS else "other"


# ---------------------------------------------------------------- stats

def new_day():
    return {"keys": 0, "textKeys": 0, "bestWPM": 0.0, "hours": [0] * 24, "apps": {}}


def clamp(value):
    try:
        value = int(value)
    except (TypeError, ValueError):
        return 0
    return min(max(value, 0), MAX_COUNT)


def valid_day_key(key):
    parts = key.split("-")
    if len(parts) != 3 or [len(p) for p in parts] != [4, 2, 2]:
        return False
    if not all(p.isascii() and p.isdigit() for p in parts):
        return False
    return 1 <= int(parts[1]) <= 12 and 1 <= int(parts[2]) <= 31


def sanitized(data):
    """Repairs or drops anything implausible in a hand-edited or damaged file."""
    clean = {"version": 1, "days": {}}
    days = data.get("days") if isinstance(data, dict) else None
    if not isinstance(days, dict):
        return clean
    for key in sorted(days)[-MAX_DAYS:]:
        day = days[key]
        if not valid_day_key(key) or not isinstance(day, dict):
            continue
        fixed = new_day()
        fixed["keys"] = clamp(day.get("keys"))
        fixed["textKeys"] = clamp(day.get("textKeys"))
        try:
            wpm = float(day.get("bestWPM", 0))
        except (TypeError, ValueError):
            wpm = 0.0
        fixed["bestWPM"] = min(max(wpm, 0.0), MAX_WPM) if wpm == wpm and wpm != float("inf") else 0.0
        hours = day.get("hours")
        if isinstance(hours, list):
            for hour in range(min(24, len(hours))):
                fixed["hours"][hour] = clamp(hours[hour])
        clean["days"][key] = fixed
    return clean


class Stats:
    def __init__(self, directory):
        self.directory = directory
        self.path = os.path.join(directory, "stats.json")
        self.live_path = os.path.join(directory, "live.json")
        self.data = self.load()
        self.stamps = collections.deque()
        self.dirty = False
        self.live_dirty = True

    def load(self):
        try:
            fd = os.open(self.path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except FileNotFoundError:
            return {"version": 1, "days": {}}
        except OSError:
            self.move_aside()
            return {"version": 1, "days": {}}
        try:
            info = os.fstat(fd)
            if not (info.st_mode & 0o170000 == 0o100000) or info.st_size > MAX_FILE_BYTES:
                raise ValueError("not a regular file of plausible size")
            raw = os.read(fd, MAX_FILE_BYTES + 1)
            return sanitized(json.loads(raw))
        except (OSError, ValueError):
            os.close(fd)
            fd = None
            self.move_aside()
            return {"version": 1, "days": {}}
        finally:
            if fd is not None:
                os.close(fd)

    def move_aside(self):
        """Never silently overwrite a file we couldn't read: it may still hold old counts."""
        try:
            os.replace(self.path, os.path.join(self.directory, "stats.corrupt.json"))
            log("keybomyd: unreadable stats.json moved to stats.corrupt.json")
        except OSError:
            pass

    def record(self, kind, now):
        if kind == "ignored":
            return
        local = time.localtime(now)
        if not 2000 <= local.tm_year <= 9999:
            return
        key = time.strftime("%Y-%m-%d", local)
        day = self.data["days"].setdefault(key, new_day())
        day["keys"] = min(day["keys"] + 1, MAX_COUNT)
        day["hours"][local.tm_hour] = min(day["hours"][local.tm_hour] + 1, MAX_COUNT)
        if kind in ("letter", "space"):
            day["textKeys"] = min(day["textKeys"] + 1, MAX_COUNT)
            day["bestWPM"] = max(day["bestWPM"], min(self.wpm(now), MAX_WPM))
        self.dirty = True
        self.live_dirty = True

    def wpm(self, now):
        """Words per minute over a full sliding minute (5 keys = 1 word). A short burst
        is averaged against idle time, so it can only under-report. In memory only."""
        if self.stamps and now < self.stamps[-1]:
            self.stamps.clear()  # clock moved backwards
        self.stamps.append(now)
        while len(self.stamps) > MAX_STAMPS:
            self.stamps.popleft()
        while self.stamps and self.stamps[0] <= now - WPM_WINDOW:
            self.stamps.popleft()
        return len(self.stamps) / KEYS_PER_WORD

    def reset(self):
        self.data = {"version": 1, "days": {}}
        self.stamps.clear()
        for name in ("stats.json", "stats.corrupt.json", ".stats.json.tmp", "live.json", ".live.json.tmp"):
            try:
                os.unlink(os.path.join(self.directory, name))
            except FileNotFoundError:
                pass
        self.dirty = True
        self.live_dirty = True
        log("keybomyd: all data deleted on request")

    def write_atomic(self, path, payload, sync):
        temp = os.path.join(self.directory, "." + os.path.basename(path) + ".tmp")
        try:
            os.unlink(temp)
        except FileNotFoundError:
            pass
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            data = payload.encode()
            view = memoryview(data)
            while view:
                view = view[os.write(fd, view):]
            if sync:
                os.fsync(fd)
        finally:
            os.close(fd)
        os.rename(temp, path)

    def save(self):
        if not self.dirty:
            return
        try:
            self.write_atomic(self.path, json.dumps(self.data, indent=2, sort_keys=True), sync=True)
            self.dirty = False
        except OSError as error:
            log(f"keybomyd: could not save stats: {error}")

    def save_live(self, devices):
        key = time.strftime("%Y-%m-%d")
        live = {
            "version": VERSION,
            "updated": int(time.time()),
            "devices": devices,
            "date": key,
            "day": self.data["days"].get(key, new_day()),
        }
        try:
            self.write_atomic(self.live_path, json.dumps(live, sort_keys=True), sync=False)
            self.live_dirty = False
        except OSError as error:
            log(f"keybomyd: could not save live stats: {error}")


# ---------------------------------------------------------------- devices

def is_keyboard(name):
    """A device that can type letters and space: rules out mice, power buttons,
    lid switches and media-key-only nodes."""
    try:
        with open(f"/sys/class/input/{name}/device/capabilities/key") as f:
            words = f.read().split()
    except OSError:
        return False
    bits = 0
    for word in words:  # most significant word first
        bits = (bits << 64) | int(word, 16)
    return all(bits >> code & 1 for code in (*LETTERS, KEY_SPACE))


class Devices:
    def __init__(self):
        self.open = {}  # fd -> event node name

    def rescan(self):
        present = set()
        try:
            names = sorted(n for n in os.listdir("/dev/input") if n.startswith("event"))
        except OSError:
            names = []
        known = set(self.open.values())
        for name in names:
            if not is_keyboard(name):
                continue
            present.add(name)
            if name in known:
                continue
            try:
                fd = os.open(f"/dev/input/{name}", os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            except OSError as error:
                log(f"keybomyd: cannot open /dev/input/{name}: {error.strerror}")
                continue
            self.open[fd] = name
            log(f"keybomyd: listening to /dev/input/{name}")
        for fd, name in list(self.open.items()):
            if name not in present:
                self.drop(fd)

    def drop(self, fd):
        name = self.open.pop(fd, None)
        try:
            os.close(fd)
        except OSError:
            pass
        if name:
            log(f"keybomyd: stopped listening to /dev/input/{name}")


# ---------------------------------------------------------------- main loop

def default_directory():
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "keybomy")


def prepare_directory(directory):
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    if os.stat(directory).st_uid != os.geteuid():
        raise PermissionError(f"{directory} is owned by someone else")


def acquire_lock(directory):
    """Two copies would double-count every key and overwrite each other's saves."""
    path = os.path.join(directory, ".lock")
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("keybomyd: another copy is already running")
        sys.exit(0)
    return fd


def main():
    make_undumpable()
    directory = sys.argv[1] if len(sys.argv) > 1 else default_directory()
    prepare_directory(directory)
    lock = acquire_lock(directory)  # noqa: F841, held for the life of the process
    reset_path = os.path.join(directory, "reset")

    stats = Stats(directory)
    devices = Devices()
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    held = set()
    last_save = last_live = last_scan = 0.0
    log(f"keybomyd {VERSION}: writing to {directory}")

    while running:
        now = time.monotonic()
        if now - last_scan >= RESCAN_EVERY:
            devices.rescan()
            last_scan = now
            if os.path.lexists(reset_path):
                stats.reset()
                os.unlink(reset_path)

        try:
            ready, _, _ = select.select(list(devices.open), [], [], 1.0)
        except InterruptedError:
            ready = []
        except OSError:
            ready = []
            devices.rescan()

        for fd in ready:
            try:
                chunk = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError as error:
                if error.errno in (errno.ENODEV, errno.EBADF, errno.EIO):
                    devices.drop(fd)  # unplugged
                    continue
                raise
            wall = time.time()
            for offset in range(0, len(chunk) - EVENT.size + 1, EVENT.size):
                _, _, kind, code, value = EVENT.unpack_from(chunk, offset)
                if kind != EV_KEY or code >= FIRST_BUTTON:
                    continue
                if code in MODIFIERS:  # modifiers alone aren't key presses, as on macOS
                    if value == 1:
                        held.add(code)
                    elif value == 0:
                        held.discard(code)
                    continue
                if value != 1:  # 0 is release, 2 is auto-repeat: held keys count once
                    continue
                stats.record(classify(code, held), wall)
            # Reduce at once and forget: nothing about which keys were pressed survives this loop.
            del chunk

        now = time.monotonic()
        if stats.live_dirty and now - last_live >= LIVE_EVERY or now - last_live >= HEARTBEAT:
            stats.save_live(len(devices.open))
            last_live = now
        if now - last_save >= SAVE_EVERY:
            stats.save()
            last_save = now

    stats.save()
    stats.save_live(0)
    log("keybomyd: stopped")


if __name__ == "__main__":
    main()
