#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

COMMAND_TIMEOUT = 3


def command_available(command):
    return shutil.which(command) is not None


def run_command(args, timeout=COMMAND_TIMEOUT):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def device(name, stable_id, dev_type, connected, battery=None, charging=False, connection="unknown"):
    return {
        "id": stable_id,
        "name": name or "Unknown device",
        "type": dev_type or "unknown",
        "connected": bool(connected),
        "battery": battery,
        "charging": bool(charging),
        "connection": connection,
    }


def get_upower_devices():
    if not command_available("upower"):
        return [], "upower is not installed"
    devices = []
    output = run_command(["upower", "-e"])
    if not output:
        return [], "upower returned no devices"
    for line in output.splitlines():
        path = line.strip()
        if not path or any(value in path for value in ("battery_BAT", "line_power", "DisplayDevice")):
            continue
        info = run_command(["upower", "-i", path])
        if not info:
            continue
        model = re.search(r"model:\s*(.*)", info)
        kind = re.search(r"device-type:\s*(.*)", info)
        percent = re.search(r"percentage:\s*(\d+)%", info)
        present = re.search(r"present:\s*(yes|no)", info)
        state = re.search(r"state:\s*(.*)", info)
        state_value = state.group(1).strip() if state else ""
        connected = present and present.group(1) == "yes"
        if not connected:
            connected = state_value not in ("", "unknown", "empty")
        devices.append(device(
            model.group(1).strip() if model else path.rsplit("/", 1)[-1],
            "upower:" + path,
            kind.group(1).strip() if kind else "unknown",
            connected,
            int(percent.group(1)) if percent else None,
            state_value == "charging",
            "upower",
        ))
    return devices, None


def get_bluetooth_devices():
    if not command_available("bluetoothctl"):
        return [], "bluetoothctl is not installed"
    devices = []
    output = run_command(["bluetoothctl", "devices"])
    if not output:
        return [], None
    for line in output.splitlines():
        match = re.match(r"Device\s+([0-9A-Fa-f:]+)\s+(.*)", line.strip())
        if not match:
            continue
        address, name = match.groups()
        info = run_command(["bluetoothctl", "info", address])
        connected = "Connected: yes" in info
        battery_match = re.search(r"Battery Percentage:\s+.*\((\d+)\)", info) or re.search(r"Battery Percentage:\s+(\d+)", info)
        lower_name = name.lower()
        if "audio-headset" in info or any(value in lower_name for value in ("audio", "buds", "head")):
            dev_type = "headphone"
        elif "input-mouse" in info or "mouse" in lower_name:
            dev_type = "mouse"
        elif "input-keyboard" in info or "keyboard" in lower_name:
            dev_type = "keyboard"
        else:
            dev_type = "unknown"
        devices.append(device(name, "bluetooth:" + address.lower(), dev_type, connected, int(battery_match.group(1)) if battery_match else None, False, "bluetooth"))
    return devices, None


def get_usb_devices():
    usb_dir = "/sys/bus/usb/devices"
    if not os.path.isdir(usb_dir):
        return [], "USB device directory is unavailable"
    devices = []
    try:
        entries = os.listdir(usb_dir)
    except OSError:
        return [], "Unable to read USB devices"
    ignored = ("xHCI Host Controller", "Bluetooth Radio", "Integrated Camera", "Root Hub")
    for entry in entries:
        base = os.path.join(usb_dir, entry)
        product_path = os.path.join(base, "product")
        try:
            with open(product_path, "r") as file:
                name = file.read().strip()
        except OSError:
            continue
        if not name or name in ignored:
            continue
        lower_name = name.lower()
        if "ite device" in lower_name or "ite tech" in lower_name:
            continue
        if "mouse" in lower_name:
            dev_type = "mouse"
        elif "keyboard" in lower_name:
            dev_type = "keyboard"
        elif any(value in lower_name for value in ("headset", "headphone", "audio")):
            dev_type = "headphone"
        else:
            dev_type = "unknown"
        devices.append(device(name, "usb:" + entry, dev_type, True, None, False, "wired"))
    return devices, None


def get_kdeconnect_devices():
    if not command_available("kdeconnect-cli"):
        return [], "kdeconnect-cli is not installed"
    devices = []
    output = run_command(["kdeconnect-cli", "-l", "--id-name-only"])
    for line in output.splitlines():
        parts = line.strip().split(" ", 1)
        if len(parts) != 2:
            continue
        dev_id, name = parts
        reachable = run_command(["kdeconnect-cli", "-d", dev_id, "--ping"]) != ""
        devices.append(device(name, "kdeconnect:" + dev_id, "phone", reachable, None, False, "kdeconnect"))
    return devices, None


def collect():
    functions = [get_kdeconnect_devices, get_bluetooth_devices, get_upower_devices, get_usb_devices]
    devices = []
    errors = []
    with ThreadPoolExecutor(max_workers=len(functions)) as executor:
        for result_devices, error in executor.map(lambda function: function(), functions):
            devices.extend(result_devices)
            if error:
                errors.append(error)
    unique = {}
    for item in devices:
        unique.setdefault(item["id"], item)
    result = sorted(unique.values(), key=lambda item: (not item["connected"], item["name"].lower()))
    return {"devices": result, "errors": errors}


print(json.dumps(collect()))
