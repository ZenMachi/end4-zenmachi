#!/usr/bin/env python3
import atexit
import select
import signal
import subprocess
import sys

processes = []


def stop_processes(*_args):
    for process in processes:
        if process and process.poll() is None:
            try:
                process.terminate()
                process.wait(timeout=1)
            except Exception:
                try:
                    process.kill()
                except Exception:
                    pass


def start(args):
    try:
        process = subprocess.Popen(
            ["stdbuf", "-oL", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        processes.append(process)
        return process
    except OSError:
        return None


signal.signal(signal.SIGTERM, stop_processes)
signal.signal(signal.SIGINT, stop_processes)
atexit.register(stop_processes)

sources = [
    start(["dbus-monitor", "--system", "type='signal',sender='org.bluez'"]),
    start(["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.UPower'"]),
    start(["dbus-monitor", "--session", "type='signal',sender='org.kde.kdeconnect'"]),
    start(["udevadm", "monitor", "--subsystem-match=usb"]),
]
streams = [source.stdout for source in sources if source and source.stdout]

if not streams:
    sys.exit(0)

try:
    while streams:
        readable, _, _ = select.select(streams, [], [])
        for stream in readable:
            line = stream.readline().decode("utf-8", errors="ignore").strip()
            if not line:
                streams.remove(stream)
                continue
            is_udev = line.startswith("KERNEL[") or line.startswith("UDEV[")
            is_dbus = (
                "sender=" in line
                and "org.freedesktop.DBus" not in line
                and "NameAcquired" not in line
                and "NameLost" not in line
            )
            if is_udev or is_dbus:
                stop_processes()
                sys.exit(0)
finally:
    stop_processes()
