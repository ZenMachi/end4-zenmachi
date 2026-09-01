#!/usr/bin/env python3
"""Screen time tracker with per-day history archiving.

Writes live data to ~/.cache/screentime.json (the widget watches this) and
archives a frozen snapshot of each day under ~/.cache/screentime_history/YYYY-MM-DD.json
so the widget can show historical screen time for any past date.

Data-loss safety:
- A stale live snapshot (from a previous day) is archived under its own date
  before a new day starts, so nothing is lost across restarts/reloads.
- Archived days are merged with the existing snapshot, keeping the more
  complete one (larger total_screentime) so counters never shrink.
"""
import os
import json
import time
import datetime
import signal
import subprocess

CACHE_DIR = os.path.expanduser("~/.cache")
HISTORY_DIR = os.path.join(CACHE_DIR, "screentime_history")
LIVE_PATH = os.path.join(CACHE_DIR, "screentime.json")
INDEX_PATH = os.path.join(HISTORY_DIR, "index.json")

running = True


def is_locked():
    lock_comms = {"hyprlock", "gtklock", "swaylock"}
    try:
        for pid in os.listdir("/proc"):
            if pid.isdigit():
                try:
                    with open(f"/proc/{pid}/comm", "r") as f:
                        comm = f.read().strip()
                        if comm in lock_comms:
                            return True
                except Exception:
                    pass
    except Exception:
        pass
    return False


def get_active_window_class():
    try:
        out = subprocess.check_output(["hyprctl", "activewindow", "-j"]).decode("utf-8")
        data = json.loads(out)
        return data.get("class", "").strip()
    except Exception:
        return ""


def read_uptime():
    try:
        with open("/proc/uptime", "r") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return 0


def date_key(dt):
    return dt.strftime("%Y-%m-%d")


def history_path(key):
    return os.path.join(HISTORY_DIR, key + ".json")


def empty_day():
    return {
        "date": date_key(datetime.datetime.now()),
        "total_screentime": 0,
        "total_uptime": 0,
        "apps": {},
        "hourly_usage": {str(i): 0 for i in range(24)},
    }


def normalize_day(data, key):
    """Ensure a day dict has the expected structure and a correct date key."""
    if not isinstance(data, dict):
        data = {}
    if "hourly_usage" not in data or not isinstance(data["hourly_usage"], dict):
        data["hourly_usage"] = {str(i): 0 for i in range(24)}
    for i in range(24):
        data["hourly_usage"].setdefault(str(i), 0)
    if "apps" not in data or not isinstance(data["apps"], dict):
        data["apps"] = {}
    data.setdefault("total_screentime", 0)
    data.setdefault("total_uptime", 0)
    data["date"] = key
    return data


def load_live():
    """Return the live snapshot dict, or None if it can't be read."""
    try:
        with open(LIVE_PATH, "r") as f:
            return json.load(f)
    except Exception:
        return None


def load_day(key):
    path = history_path(key)
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r") as f:
            loaded = json.load(f)
        return normalize_day(loaded, key)
    except Exception:
        return None


def write_json(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        pass


def list_history_days():
    """Return sorted list of archive date keys (YYYY-MM-DD)."""
    try:
        if not os.path.isdir(HISTORY_DIR):
            return []
        keys = []
        for name in os.listdir(HISTORY_DIR):
            if name.endswith(".json") and name not in ("index.json", "index.json.tmp"):
                keys.append(name[:-5])
        keys.sort()
        return keys
    except Exception:
        return []


def write_index():
    days = list_history_days()
    index = {d: {"screentime": (load_day(d) or {}).get("total_screentime", 0)} for d in days}
    write_json(INDEX_PATH, index)


def merge_day(existing, incoming):
    """Return the more complete snapshot (larger total_screentime wins)."""
    if existing is None:
        return incoming
    if incoming is None:
        return existing
    if incoming.get("total_screentime", 0) >= existing.get("total_screentime", 0):
        return incoming
    return existing


def archive_day(data):
    """Freeze a day snapshot using its own stored date, merging with any
    existing archive so counters never shrink. Returns the merged snapshot."""
    key = data.get("date") if isinstance(data, dict) and data.get("date") else date_key(datetime.datetime.now())
    data = normalize_day(data, key)
    existing = load_day(key)
    merged = merge_day(existing, data)
    merged = normalize_day(merged, key)
    merged["total_uptime"] = read_uptime()
    write_json(history_path(key), merged)
    write_index()
    return merged


def handle_exit(signum, frame):
    global running
    running = False


def main():
    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)

    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(HISTORY_DIR, exist_ok=True)

    current_day = date_key(datetime.datetime.now())

    # Recover the live snapshot. It may be stale (from a previous day); in that
    # case archive it under its own date so the data is not lost.
    live = load_live()
    recovered = None
    if live is not None and isinstance(live.get("date"), str):
        live_date = live["date"]
        if live_date == current_day:
            recovered = normalize_day(live, current_day)
        else:
            archive_day(live)
    if recovered is None:
        recovered = load_day(current_day)
    data = recovered if recovered is not None else empty_day()
    data = normalize_day(data, current_day)

    # Keep today's archive in sync and use the merged snapshot if it had more.
    data = archive_day(data)

    interval = 2  # seconds
    try:
        while running:
            new_day = date_key(datetime.datetime.now())
            if new_day != current_day:
                # Date rolled over: finalize the old day, start fresh today.
                archive_day(data)
                current_day = new_day
                data = empty_day()
                data["date"] = current_day
                archive_day(data)

            data["total_uptime"] = read_uptime()

            if not is_locked():
                active_class = get_active_window_class()
                data["total_screentime"] += interval
                curr_hour = str(datetime.datetime.now().hour)
                data["hourly_usage"][curr_hour] = data["hourly_usage"].get(curr_hour, 0) + interval
                if active_class:
                    data["apps"][active_class] = data["apps"].get(active_class, 0) + interval

            write_json(LIVE_PATH, data)
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally:
        data = archive_day(data)
        write_json(LIVE_PATH, data)


if __name__ == "__main__":
    main()
