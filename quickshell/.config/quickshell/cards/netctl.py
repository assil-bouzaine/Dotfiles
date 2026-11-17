#!/usr/bin/env python3
"""Back end of the network card (shell.qml). Every nmcli call lives here.

Each subcommand prints one JSON object on stdout (`speed` prints one per
sample). Secrets never go on a command line, because /proc/<pid>/cmdline can
be read by anyone. The card passes them in NETCARD_SECRET, which only this
user can read, and this script feeds them to `nmcli connection edit` on stdin.

Ported from the Omarchy 4.5 network panel and its helpers (MIT,
github.com/basecamp/omarchy): omarchy-network-status, -band, -qr, omarchy-dns
and the panel's enterprise connect script. Changes: the DNS choice is stored
per connection profile, so no root is needed (this machine has no
systemd-resolved), the band and bitrate come from nmcli instead of iw, and
the speed test uses Cloudflare's public endpoints.

    netctl.py status                 connection, stats, pings, band, DNS
    netctl.py list                   networks in range + saved ones
    netctl.py rescan
    netctl.py connect <ssid> [--identity <user>]   (NETCARD_SECRET = password)
    netctl.py disconnect
    netctl.py forget <ssid>
    netctl.py radio on|off
    netctl.py band auto|2.4|5|6
    netctl.py dns DHCP|Cloudflare|Google|Custom [servers...]
    netctl.py qr                     QR code PNG for the current Wi-Fi
    netctl.py speed                  download then upload, streamed samples
"""

import ipaddress
import json
import os
import subprocess
import sys
import threading
import time
import uuid as uuidlib

sys.dont_write_bytecode = True

PROBE = "1.1.1.1"
ENV = dict(os.environ, LC_ALL="C")   # nmcli translates its state words
DNS = {
    "Cloudflare": ("1.1.1.1 1.0.0.1", "2606:4700:4700::1111 2606:4700:4700::1001"),
    "Google": ("8.8.8.8 8.8.4.4", "2001:4860:4860::8888 2001:4860:4860::8844"),
}
NM_BAND = {"2.4": "bg", "5": "a", "6": "6GHz"}


def out(obj):
    print(json.dumps(obj), flush=True)


def run(*cmd, timeout=30, stdin=None):
    """(ok, stdout, stderr). Never raises."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           env=ENV, input=stdin)
        return p.returncode == 0, p.stdout, p.stderr.strip()
    except subprocess.TimeoutExpired:
        return False, "", "timed out"
    except OSError as e:
        return False, "", str(e)


def nm(*args, **kw):
    return run("nmcli", *args, **kw)


def fields(line):
    """Split one `nmcli -t` line. nmcli escapes ':' and '\\' inside values."""
    parts, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def blocks(text):
    """`nmcli -t -f a,b connection show X Y` output -> one dict per profile."""
    res, cur = [], {}
    for line in text.splitlines():
        if not line.strip():
            if cur:
                res.append(cur)
            cur = {}
            continue
        key, _, val = line.partition(":")
        cur[key] = val
    if cur:
        res.append(cur)
    return res


def band_for(freq):
    digits = "".join(c for c in str(freq).split(".")[0] if c.isdigit())
    if not digits:
        return ""
    mhz = int(digits)
    if 2400 <= mhz < 2500:
        return "2.4"
    if 4900 <= mhz < 5925:
        return "5"
    if 5925 <= mhz < 7125:
        return "6"
    return ""


def wifi_device():
    """(device, state) of the first Wi-Fi device, or (None, '')."""
    ok, text, _ = nm("-t", "-f", "DEVICE,TYPE,STATE", "device")
    for line in text.splitlines():
        f = fields(line)
        if len(f) >= 3 and f[1] == "wifi":
            return f[0], f[2]
    return None, ""


def wifi_profiles():
    """Saved Wi-Fi profiles: [{uuid, ssid, band, keymgmt, dns}]."""
    ok, text, _ = nm("-t", "-f", "UUID,TYPE", "connection", "show")
    uuids = [fields(l)[0] for l in text.splitlines() if fields(l)[1:2] == ["802-11-wireless"]]
    if not uuids:
        return []
    ok, text, _ = nm("-t", "-e", "no", "-f",
                     "connection.uuid,802-11-wireless.ssid,802-11-wireless.band,"
                     "802-11-wireless-security.key-mgmt",
                     "connection", "show", *uuids)
    return [{"uuid": b.get("connection.uuid", ""), "ssid": b.get("802-11-wireless.ssid", ""),
             "band": b.get("802-11-wireless.band", ""),
             "keymgmt": b.get("802-11-wireless-security.key-mgmt", "")}
            for b in blocks(text)]


def scan_rows(dev):
    """Access points from NetworkManager's cache (no forced scan)."""
    args = ["-t", "-f", "IN-USE,SIGNAL,SECURITY,FREQ,RATE,SSID", "device", "wifi", "list"]
    if dev:
        args += ["ifname", dev]
    ok, text, _ = nm(*args, "--rescan", "no", timeout=15)
    rows = []
    for line in text.splitlines():
        f = fields(line)
        if len(f) < 6:
            continue
        rows.append({"used": f[0] == "*", "signal": int(f[1] or 0), "security": f[2],
                     "freq": f[3], "rate": f[4], "ssid": ":".join(f[5:])})
    return rows


def ping_ms(host):
    if not host:
        return None
    ok, text, _ = run("ping", "-n", "-c", "1", "-W", "1", host, timeout=3)
    for part in text.split():
        if part.startswith("time=") or part.startswith("time<"):
            try:
                return float(part[5:])
            except ValueError:
                return None
    return None


def dns_provider(v4):
    servers = v4.replace(",", " ").split()
    if not servers:
        return "DHCP"
    if "1.1.1.1" in servers:
        return "Cloudflare"
    if "8.8.8.8" in servers:
        return "Google"
    return "Custom"


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


# ── status ────────────────────────────────────────────────────────────────

def cmd_status():
    res = {"kind": "disconnected"}
    ok, text, _ = run("ip", "-j", "route", "get", PROBE, timeout=5)
    route = {}
    try:
        route = json.loads(text)[0] if ok else {}
    except (ValueError, IndexError):
        pass
    iface, gateway = route.get("dev", ""), route.get("gateway", "")

    # Pings run alongside the nmcli calls below.
    pings = {}
    threads = [threading.Thread(target=lambda k=k, h=h: pings.__setitem__(k, ping_ms(h)))
               for k, h in (("router_ping", gateway), ("internet_ping", PROBE if iface else ""))]
    for t in threads:
        t.start()

    _, radio, _ = nm("radio", "wifi")
    dev, dev_state = wifi_device()
    res["wifi_enabled"] = radio.strip() == "enabled"
    res["wifi_device"] = dev or ""
    res["wifi_state"] = dev_state
    _, conn, _ = nm("networking", "connectivity")
    res["connectivity"] = conn.strip() or "unknown"

    if iface:
        res["iface"] = iface
        res["gateway"] = gateway
        res["ip"] = route.get("prefsrc", "")
        res["rx_bytes"] = read_int(f"/sys/class/net/{iface}/statistics/rx_bytes")
        res["tx_bytes"] = read_int(f"/sys/class/net/{iface}/statistics/tx_bytes")
        ok, text, _ = nm("-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION,GENERAL.CON-UUID,"
                         "CAPABILITIES.SPEED", "device", "show", iface)
        g = dict(l.split(":", 1) for l in text.splitlines() if ":" in l)
        uuid = g.get("GENERAL.CON-UUID", "")
        res["profile"] = g.get("GENERAL.CONNECTION", "")
        if os.path.isdir(f"/sys/class/net/{iface}/wireless"):
            res["kind"] = "wifi"
            rows = scan_rows(iface)
            cur = next((r for r in rows if r["used"]), None)
            res["ssid"] = cur["ssid"] if cur else res["profile"]
            res["signal"] = cur["signal"] if cur else -1
            res["freq"] = cur["freq"] if cur else ""
            # Negotiated link speed; the scan's RATE is only the AP's maximum.
            res["rate"] = g.get("CAPABILITIES.SPEED", "").replace("unknown", "").strip()
            band = band_for(res["freq"])
            avail = {band} if band else set()
            avail |= {band_for(r["freq"]) for r in rows if r["ssid"] == res["ssid"]}
            avail.discard("")
            res["band"] = band
            res["bands"] = sorted(avail, key=float)
        else:
            res["kind"] = "ethernet"
            res["speed"] = read_int(f"/sys/class/net/{iface}/speed")
        if uuid:
            ok, text, _ = nm("-t", "-e", "no", "-f", "802-11-wireless.band,ipv4.dns",
                             "connection", "show", "uuid", uuid)
            p = blocks(text)[0] if text.strip() else {}
            res["band_selected"] = {"bg": "2.4", "a": "5", "6GHz": "6"}.get(
                p.get("802-11-wireless.band", ""), "auto")
            res["dns"] = dns_provider(p.get("ipv4.dns", ""))
            res["dns_servers"] = p.get("ipv4.dns", "")
    elif dev_state.startswith("connecting"):
        res["kind"] = "connecting"

    for t in threads:
        t.join()
    res.update(pings)
    out(res)


# ── networks ──────────────────────────────────────────────────────────────

def cmd_list():
    dev, _ = wifi_device()
    profiles = wifi_profiles()
    known = {}
    for p in profiles:
        known.setdefault(p["ssid"], []).append(p["uuid"])
    best = {}
    for r in scan_rows(dev):
        if not r["ssid"]:
            continue   # hidden networks need their name typed in
        sec = r["security"].strip()
        net = {"ssid": r["ssid"], "strength": r["signal"], "connected": r["used"],
               "security": sec,
               "open": sec in ("", "--") or sec == "OWE",
               "enterprise": "802.1X" in sec,
               "known": r["ssid"] in known}
        old = best.get(r["ssid"])
        if not old or (net["connected"], net["strength"]) > (old["connected"], old["strength"]):
            if old and old["connected"]:
                net["connected"] = True
            best[r["ssid"]] = net
    nets = sorted(best.values(),
                  key=lambda n: (not n["connected"], not n["known"], -n["strength"]))
    out({"networks": nets})


def cmd_rescan():
    ok, _, err = nm("device", "wifi", "rescan", timeout=15)
    out({"ok": ok, "error": err})


def failure_reason(err):
    e = err.lower()
    if "secrets were required" in e or "no secrets" in e or "supplicant" in e \
            or "802-1x" in e or "802-11-wireless-security" in e or "auth" in e:
        return "wrong_password"
    if "no network with ssid" in e or "not found" in e:
        return "network_lost"
    if "timeout" in e or "timed out" in e:
        return "timeout"
    return "failed"


def edit_secret(uuid, key, secret):
    """Store a secret through nmcli's editor, which reads it from stdin."""
    script = f"set {key} {secret}\nsave\nquit\n"
    ok, _, err = nm("connection", "edit", "uuid", uuid, stdin=script, timeout=15)
    return ok


def up(uuid):
    ok, text, err = nm("-w", "30", "connection", "up", "uuid", uuid, timeout=40)
    return ok, err or text


def cmd_connect(ssid, identity=None):
    secret = os.environ.get("NETCARD_SECRET", "")
    profiles = [p for p in wifi_profiles() if p["ssid"] == ssid]
    nets = [r for r in scan_rows(wifi_device()[0]) if r["ssid"] == ssid]
    sec = max(nets, key=lambda r: r["signal"])["security"] if nets else ""

    if profiles and not secret:
        ok, err = up(profiles[0]["uuid"])
        return out({"ok": ok, "reason": "" if ok else failure_reason(err), "error": err})

    if profiles and secret:
        # A saved network whose password was wrong: store the new one and retry.
        p = profiles[0]
        key = "802-1x.password" if "eap" in p["keymgmt"] else "802-11-wireless-security.psk"
        if identity and "eap" in p["keymgmt"]:
            nm("connection", "modify", "uuid", p["uuid"], "802-1x.identity", identity)
        edit_secret(p["uuid"], key, secret)
        ok, err = up(p["uuid"])
        return out({"ok": ok, "reason": "" if ok else failure_reason(err), "error": err})

    if not nets:
        return out({"ok": False, "reason": "network_lost", "error": "not in range"})

    if sec in ("", "--") or sec == "OWE" or "WEP" in sec:
        # Open, Enhanced Open and the rare WEP network: let nmcli work it out.
        args = ["-w", "30", "device", "wifi", "connect", ssid]
        if secret:
            args += ["password", secret]   # WEP only; nothing better exists for it
        ok, text, err = nm(*args, timeout=40)
        return out({"ok": ok, "reason": "" if ok else failure_reason(err), "error": err})

    if not secret:
        return out({"ok": False, "reason": "needs_password", "error": ""})

    u = str(uuidlib.uuid4())
    if "802.1X" in sec:
        # WPA Enterprise as PEAP / MSCHAPv2, the setup almost every campus uses.
        args = ["wifi-sec.key-mgmt", "wpa-eap", "802-1x.eap", "peap",
                "802-1x.phase2-auth", "mschapv2", "802-1x.identity", identity or "",
                "802-1x.auth-timeout", "8"]
        key = "802-1x.password"
    else:
        mgmt = "sae" if "WPA3" in sec and "WPA2" not in sec and "WPA1" not in sec else "wpa-psk"
        args = ["wifi-sec.key-mgmt", mgmt]
        key = "802-11-wireless-security.psk"
    ok, _, err = nm("connection", "add", "type", "wifi", "con-name", ssid, "ssid", ssid,
                    "connection.uuid", u, *args)
    if ok and edit_secret(u, key, secret):
        ok, err = up(u)
    else:
        ok = False
    if not ok:
        nm("connection", "delete", "uuid", u)   # don't keep a profile that can't connect
    out({"ok": ok, "reason": "" if ok else failure_reason(err), "error": err})


def cmd_disconnect():
    dev, _ = wifi_device()
    ok, _, err = nm("device", "disconnect", dev) if dev else (False, "", "no Wi-Fi device")
    out({"ok": ok, "error": err})


def cmd_forget(ssid):
    uuids = [p["uuid"] for p in wifi_profiles() if p["ssid"] == ssid]
    ok = bool(uuids)
    for u in uuids:
        ok = nm("connection", "delete", "uuid", u)[0] and ok
    out({"ok": ok})


def cmd_radio(state):
    if state == "on":
        run("rfkill", "unblock", "wifi")
    ok, _, err = nm("radio", "wifi", state)
    out({"ok": ok, "error": err})


# ── band ──────────────────────────────────────────────────────────────────

def cmd_band(target):
    dev, _ = wifi_device()
    ok, text, _ = nm("-t", "-f", "GENERAL.CON-UUID", "device", "show", dev or "")
    uuid = text.partition(":")[2].strip()
    if not uuid:
        return out({"ok": False, "error": "No active Wi-Fi connection"})
    _, prev, _ = nm("-g", "802-11-wireless.band", "connection", "show", "uuid", uuid)
    prev = prev.strip()
    want = "" if target == "auto" else NM_BAND[target]
    if prev == want:
        return out({"ok": True})
    nm("connection", "modify", "uuid", uuid, "802-11-wireless.band", want)
    # A band change only lands on reassociation. If the radio can't come back
    # on the new band, put the old setting back rather than stay offline.
    ok, err = up(uuid)
    if not ok:
        nm("connection", "modify", "uuid", uuid, "802-11-wireless.band", prev)
        up(uuid)
        return out({"ok": False, "error": f"Couldn't connect on {target} GHz, kept the old band"})
    out({"ok": True})


# ── DNS ───────────────────────────────────────────────────────────────────

def cmd_dns(provider, servers):
    if provider == "Custom":
        v4, v6 = [], []
        for s in " ".join(servers).replace(",", " ").split():
            try:
                (v6 if ipaddress.ip_address(s).version == 6 else v4).append(s)
            except ValueError:
                return out({"ok": False, "error": f"Not an IP address: {s}"})
        if not v4 and not v6:
            return out({"ok": False, "error": "Type at least one DNS server"})
        v4, v6 = " ".join(v4), " ".join(v6)
    elif provider == "DHCP":
        v4 = v6 = ""
    else:
        v4, v6 = DNS[provider]
    auto = "no" if provider != "DHCP" else "yes"
    ignore = "yes" if auto == "no" else "no"
    ok, text, _ = nm("-t", "-f", "UUID,TYPE", "connection", "show")
    good = True
    for line in text.splitlines():
        u, kind = (fields(line) + [""])[:2]
        if kind not in ("802-11-wireless", "802-3-ethernet"):
            continue
        good = nm("connection", "modify", "uuid", u,
                  "ipv4.ignore-auto-dns", ignore, "ipv4.dns", v4,
                  "ipv6.ignore-auto-dns", ignore, "ipv6.dns", v6)[0] and good
    # Push the change onto the live connections without reconnecting.
    _, text, _ = nm("-t", "-f", "DEVICE,TYPE,STATE", "device")
    for line in text.splitlines():
        d, kind, state = (fields(line) + ["", ""])[:3]
        if kind in ("wifi", "ethernet") and state == "connected":
            nm("device", "reapply", d)
    out({"ok": good, "error": "" if good else "Some profiles could not be changed"})


# ── share as QR ───────────────────────────────────────────────────────────

def qr_escape(v):
    for c in "\\;,:\"":
        v = v.replace(c, "\\" + c)
    return v


def cmd_qr():
    dev, _ = wifi_device()
    ok, text, _ = nm("-t", "-f", "GENERAL.CON-UUID", "device", "show", dev or "")
    uuid = text.partition(":")[2].strip()
    if not uuid or uuid == "--":
        return out({"ok": False, "error": "Not connected to Wi-Fi"})
    ok, text, err = nm("--show-secrets", "-e", "no", "-g",
                       "802-11-wireless.ssid,802-11-wireless-security.key-mgmt,"
                       "802-11-wireless-security.psk,802-11-wireless.hidden,"
                       "802-11-wireless-security.wep-key0",
                       "connection", "show", "uuid", uuid)
    f = (text.rstrip("\n").split("\n") + [""] * 5)[:5]
    ssid, mgmt, psk, hidden, wep = f
    if "eap" in mgmt or "ieee8021x" in mgmt:
        return out({"ok": False, "error": "Enterprise Wi-Fi has no password to share"})
    if mgmt and mgmt != "none":
        security, password = "WPA", psk
        if not psk:
            return out({"ok": False, "error": "Couldn't read the Wi-Fi password"})
    elif wep:
        security, password = "WEP", wep
    else:
        security, password = "nopass", ""
    payload = f"WIFI:T:{security};S:{qr_escape(ssid)};P:{qr_escape(password)};"
    if hidden == "yes":
        payload += "H:true;"
    payload += ";"
    folder = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "netcard")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    for old in os.listdir(folder):
        if old.startswith("qr-"):
            os.remove(os.path.join(folder, old))
    path = os.path.join(folder, f"qr-{int(time.time() * 1000)}.png")
    ok, _, err = run("qrencode", "-t", "PNG", "-s", "8", "-m", "2", "-o", path, stdin=payload)
    if not ok:
        return out({"ok": False, "error": err or "qrencode failed"})
    out({"ok": True, "ssid": ssid, "password": password, "security": security, "path": path})


# ── speed test ────────────────────────────────────────────────────────────

def cmd_speed(seconds=8.0):
    """Download, then upload, against speed.cloudflare.com. Prints a sample
    every quarter second: {"phase": "down"|"up", "rate": bytes/s, "progress": 0..1},
    then {"phase": ..., "done": true, "rate": average bytes/s}."""
    import http.client
    import ssl

    ctx = ssl.create_default_context()
    headers = {"User-Agent": "netcard-speedtest"}

    def measure(phase, step):
        total, start, last, last_total = 0, time.monotonic(), time.monotonic(), 0
        try:
            while time.monotonic() - start < seconds:
                conn = http.client.HTTPSConnection("speed.cloudflare.com", timeout=10, context=ctx)
                for n in step(conn):
                    total += n
                    now = time.monotonic()
                    if now - last >= 0.25:
                        out({"phase": phase, "rate": (total - last_total) / (now - last),
                             "progress": min(1.0, (now - start) / seconds)})
                        last, last_total = now, total
                    if now - start >= seconds:
                        break
                conn.close()
        except (OSError, http.client.HTTPException) as e:
            out({"phase": phase, "done": True, "error": str(e), "rate": 0})
            return False
        elapsed = time.monotonic() - start
        out({"phase": phase, "done": True, "rate": total / elapsed if elapsed else 0})
        return True

    def down(conn):
        conn.request("GET", "/__down?bytes=50000000", headers=headers)
        r = conn.getresponse()
        while True:
            chunk = r.read(65536)
            if not chunk:
                return
            yield len(chunk)

    blob = os.urandom(1 << 20)

    def upl(conn):
        size = 4 << 20
        conn.putrequest("POST", "/__up")
        conn.putheader("User-Agent", headers["User-Agent"])
        conn.putheader("Content-Type", "application/octet-stream")
        conn.putheader("Content-Length", str(size))
        conn.endheaders()
        for _ in range(size // len(blob)):
            conn.send(blob)
            yield len(blob)
        conn.getresponse().read()

    if measure("down", down):
        measure("up", upl)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(2)
    c = a[0]
    if c == "status":
        cmd_status()
    elif c == "list":
        cmd_list()
    elif c == "rescan":
        cmd_rescan()
    elif c == "connect" and len(a) >= 2:
        ident = a[a.index("--identity") + 1] if "--identity" in a else None
        cmd_connect(a[1], ident)
    elif c == "disconnect":
        cmd_disconnect()
    elif c == "forget" and len(a) == 2:
        cmd_forget(a[1])
    elif c == "radio" and a[1:] in (["on"], ["off"]):
        cmd_radio(a[1])
    elif c == "band" and len(a) == 2 and a[1] in ("auto", "2.4", "5", "6"):
        cmd_band(a[1])
    elif c == "dns" and len(a) >= 2 and a[1] in ("DHCP", "Cloudflare", "Google", "Custom"):
        cmd_dns(a[1], a[2:])
    elif c == "qr":
        cmd_qr()
    elif c == "speed":
        cmd_speed()
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
