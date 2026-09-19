#!/usr/bin/env python3
import json
import os
import random
import re
import select
import signal
import subprocess
import sys
import time

avahi_proc = None
conn_proc = None
qr_file_path = "/tmp/adb_pair_qr.png"

def handle_exit(signum, frame):
    cleanup()
    sys.exit(0)

def cleanup():
    global avahi_proc, conn_proc
    if avahi_proc:
        try:
            avahi_proc.terminate()
            avahi_proc.wait(timeout=0.5)
        except Exception:
            try:
                avahi_proc.kill()
            except Exception:
                pass
        avahi_proc = None
    if conn_proc:
        try:
            conn_proc.terminate()
            conn_proc.wait(timeout=0.5)
        except Exception:
            try:
                conn_proc.kill()
            except Exception:
                pass
        conn_proc = None

signal.signal(signal.SIGTERM, handle_exit)
signal.signal(signal.SIGINT, handle_exit)
signal.signal(signal.SIGHUP, handle_exit)

def log_event(event_type, **kwargs):
    msg = {"event": event_type, **kwargs}
    print(json.dumps(msg), flush=True)

def main():
    global avahi_proc, conn_proc, qr_file_path

    # Name must adhere to RFC6335 service names: <= 15 chars, letters/digits/hyphens
    name = f"adb-pair-{random.randint(1000, 9999)}"
    code = f"{random.randint(100000, 999999)}"
    payload = f"WIFI:T:ADB;S:{name};P:{code};;"

    # 1. Generate QR code
    try:
        subprocess.run(["qrencode", "-s", "8", "-m", "2", "-o", qr_file_path, payload], check=True)
    except Exception as e:
        log_event("error", message=f"Failed to generate QR code: {e}")
        cleanup()
        sys.exit(1)

    log_event("qr_ready", qr_path=qr_file_path, name=name, code=code, payload=payload)

    # 2. Listen on mDNS for _adb-tls-pairing._tcp with stdbuf line-buffering
    try:
        avahi_proc = subprocess.Popen(
            ["stdbuf", "-oL", "avahi-browse", "-r", "-p", "_adb-tls-pairing._tcp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
    except Exception as e:
        log_event("error", message=f"Failed to start avahi-browse: {e}")
        cleanup()
        sys.exit(1)

    start_time = time.time()
    device_ip = None
    pairing_port = None
    last_heartbeat = start_time
    total_timeout = 120
    candidate_ip = None
    candidate_port = None
    candidate_time = None

    # Wait for service advertisement
    while time.time() - start_time < total_timeout:
        # Detect if avahi-browse terminated
        if avahi_proc.poll() is not None:
            log_event("error", message="mDNS discovery process terminated unexpectedly.")
            cleanup()
            sys.exit(1)

        # Non-blocking poll for data with 0.5s timeout
        rlist, _, _ = select.select([avahi_proc.stdout], [], [], 0.5)

        now = time.time()
        # Periodic heartbeat every 5s so UI can show remaining time
        if now - last_heartbeat >= 5:
            remaining = max(0, int(total_timeout - (now - start_time)))
            log_event("waiting", remaining=remaining)
            last_heartbeat = now

        # If a fallback candidate was found and 2.5s elapsed without exact match, use candidate
        if candidate_ip and candidate_time and (now - candidate_time >= 2.5):
            device_ip = candidate_ip
            pairing_port = candidate_port
            log_event("discovered", ip=device_ip, port=pairing_port, name="fallback-service")
            break

        if not rlist:
            continue

        line = avahi_proc.stdout.readline()
        if not line:
            # Pipe closed / EOF
            break

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
                    # Check matching criteria
                    if service_inst == name or name in service_inst or service_inst.startswith("adb-pair"):
                        device_ip = ip
                        pairing_port = port
                        log_event("discovered", ip=ip, port=port, name=service_inst)
                        break
                    elif not candidate_ip:
                        candidate_ip = ip
                        candidate_port = port
                        candidate_time = time.time()

    if avahi_proc:
        try:
            avahi_proc.terminate()
            avahi_proc.wait(timeout=0.5)
        except Exception:
            try:
                avahi_proc.kill()
            except Exception:
                pass
        avahi_proc = None

    if not device_ip or not pairing_port:
        log_event("timeout", message="Pairing timed out. Ensure your phone and PC are on the same Wi-Fi network.")
        cleanup()
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
        combined = f"{pair_res.stdout}\n{pair_res.stderr}".strip()
        if pair_res.returncode == 0 or "Successfully paired" in pair_res.stdout:
            log_event("paired_success", ip=device_ip, port=pairing_port, output=pair_res.stdout.strip())
        else:
            err_msg = pair_res.stderr.strip() or pair_res.stdout.strip() or "Pairing rejected"
            log_event("error", message=f"Pairing failed: {err_msg}")
            cleanup()
            sys.exit(1)
    except Exception as e:
        log_event("error", message=f"adb pair error: {e}")
        cleanup()
        sys.exit(1)

    # 4. Discover connect port and connect automatically
    connect_port = None
    try:
        conn_proc = subprocess.Popen(
            ["stdbuf", "-oL", "avahi-browse", "-r", "-p", "_adb-tls-connect._tcp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
        c_start = time.time()
        while time.time() - c_start < 8:
            if conn_proc.poll() is not None:
                break
            rlist, _, _ = select.select([conn_proc.stdout], [], [], 0.5)
            if not rlist:
                continue
            c_line = conn_proc.stdout.readline()
            if not c_line:
                break
            c_line = c_line.strip()
            if c_line.startswith("="):
                c_parts = c_line.split(";")
                if len(c_parts) >= 9:
                    if c_parts[2] == "IPv4" and c_parts[7] == device_ip:
                        connect_port = c_parts[8]
                        break
        if conn_proc:
            try:
                conn_proc.terminate()
                conn_proc.wait(timeout=0.5)
            except Exception:
                try:
                    conn_proc.kill()
                except Exception:
                    pass
            conn_proc = None
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

    cleanup()

if __name__ == "__main__":
    main()
