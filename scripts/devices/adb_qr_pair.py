#!/usr/bin/env python3
import json
import os
import random
import re
import signal
import subprocess
import sys
import time

avahi_proc = None

def handle_exit(signum, frame):
    global avahi_proc
    if avahi_proc:
        try:
            avahi_proc.kill()
        except Exception:
            pass
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_exit)
signal.signal(signal.SIGINT, handle_exit)

def log_event(event_type, **kwargs):
    msg = {"event": event_type, **kwargs}
    print(json.dumps(msg), flush=True)

def main():
    global avahi_proc
    qr_file = "/tmp/adb_pair_qr.png"
    name = f"adb-pair-{random.randint(1000, 9999)}"
    code = f"{random.randint(100000, 999999)}"
    payload = f"WIFI:T:ADB;S:{name};P:{code};;"

    # 1. Generate QR code
    try:
        subprocess.run(["qrencode", "-s", "8", "-m", "2", "-o", qr_file, payload], check=True)
    except Exception as e:
        log_event("error", message=f"Failed to generate QR code: {e}")
        sys.exit(1)

    log_event("qr_ready", qr_path=qr_file, name=name, code=code, payload=payload)

    # 2. Listen on mDNS for _adb-tls-pairing._tcp
    try:
        avahi_proc = subprocess.Popen(
            ["avahi-browse", "-r", "-p", "_adb-tls-pairing._tcp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True
        )
    except Exception as e:
        log_event("error", message=f"Failed to start avahi-browse: {e}")
        sys.exit(1)

    start_time = time.time()
    device_ip = None
    pairing_port = None

    # Wait for service advertisement (timeout 120 seconds)
    while time.time() - start_time < 120:
        line = avahi_proc.stdout.readline()
        if not line:
            time.sleep(0.1)
            continue
        line = line.strip()
        # Look for resolved IPv4 service: =;<iface>;IPv4;<name>;_adb-tls-pairing._tcp;...
        if line.startswith("="):
            parts = line.split(";")
            if len(parts) >= 9:
                proto = parts[2]
                service_inst = parts[3]
                ip = parts[7]
                port = parts[8]
                if proto == "IPv4" and ip and port and port.isdigit():
                    device_ip = ip
                    pairing_port = port
                    log_event("discovered", ip=ip, port=port, name=service_inst)
                    break

    if avahi_proc:
        try:
            avahi_proc.terminate()
            avahi_proc.wait(timeout=1)
        except Exception:
            avahi_proc.kill()
        avahi_proc = None

    if not device_ip or not pairing_port:
        log_event("timeout", message="Pairing timed out. Phone did not scan or mDNS was blocked.")
        sys.exit(1)

    # 3. Execute adb pair
    log_event("pairing", ip=device_ip, port=pairing_port)
    try:
        pair_res = subprocess.run(
            ["adb", "pair", f"{device_ip}:{pairing_port}", code],
            capture_output=True,
            text=True,
            timeout=15
        )
        if pair_res.returncode == 0 or "Successfully paired" in pair_res.stdout:
            log_event("paired_success", ip=device_ip, port=pairing_port, output=pair_res.stdout.strip())
        else:
            err_msg = pair_res.stderr.strip() or pair_res.stdout.strip()
            log_event("error", message=f"Pairing failed: {err_msg}")
            sys.exit(1)
    except Exception as e:
        log_event("error", message=f"adb pair error: {e}")
        sys.exit(1)

    # 4. Attempt to discover connect port and connect automatically
    connect_port = None
    try:
        conn_check = subprocess.Popen(
            ["avahi-browse", "-r", "-p", "_adb-tls-connect._tcp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True
        )
        c_start = time.time()
        while time.time() - c_start < 5:
            c_line = conn_check.stdout.readline()
            if not c_line:
                time.sleep(0.1)
                continue
            c_line = c_line.strip()
            if c_line.startswith("="):
                c_parts = c_line.split(";")
                if len(c_parts) >= 9:
                    if c_parts[2] == "IPv4" and c_parts[7] == device_ip:
                        connect_port = c_parts[8]
                        break
        conn_check.terminate()
    except Exception:
        pass

    if connect_port:
        try:
            conn_res = subprocess.run(
                ["adb", "connect", f"{device_ip}:{connect_port}"],
                capture_output=True,
                text=True,
                timeout=10
            )
            log_event("connected", ip=device_ip, port=connect_port, output=conn_res.stdout.strip())
        except Exception as e:
            log_event("paired_ready_connect", ip=device_ip, message=f"Paired! Connect manually on port {connect_port}")
    else:
        log_event("paired_ready_connect", ip=device_ip, message="Paired successfully! Connect with your device's port.")

if __name__ == "__main__":
    main()
