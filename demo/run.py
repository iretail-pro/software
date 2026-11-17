#!/usr/bin/env python3
"""The iRetail PRO demo: every pilot store of deploy's demo/pilots in one
container, with nothing kept when it stops (README, "The demo").

PostgreSQL 17 and Redis 7 for all of them, one store node per pilot (each
its own organization, database and Redis database), the device gateway
with the emulated printers, scale, scanner and card terminals, and nginx
serving, on one port per store, the back office and the register in the
browser with the store's API on the same origin. Port 8080 is the start
page that lists what to open and the demo's tokens.

Everything here is invented and thrown away when the container stops: the
PINs and tokens it prints are the demo's own, never a real store's.
"""

import base64
import html
import json
import os
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

SRV = Path("/srv/demo")
STATE = Path("/var/lib/iretail-demo")
WEB_ROOT = Path("/run/iretail-demo/www")
PG_DATA = STATE / "pg"
PG_BIN = Path("/usr/lib/postgresql/17/bin")
GIFT_KEY = STATE / "gift-card.key"

PIN = os.environ.get("DEMO_PIN", "246810")
LOGIN = "admin"
GATEWAY_TOKEN = "iretail-demo"
RELEASE_URL = "https://github.com/iretail-pro/software/releases/latest"

# The pilots in the order the start page lists them; each gets the port
# its browser apps and API answer on (8081 to 8087) and a node behind it.
STORES = [
    ("supermarket", "Supermarket", 8081),
    ("pharmacy", "Pharmacy", 8082),
    ("grocery", "Grocery", 8083),
    ("coffee-shop", "Coffee shop", 8084),
    ("pizzeria", "Pizzeria", 8085),
    ("apparel", "Apparel (variants)", 8086),
    ("electronics", "Electronics (serial numbers)", 8087),
]
GUEST_PORT = 8088  # the pizzeria's guest menu, by a table's QR code

procs: list[subprocess.Popen] = []
stopping = threading.Event()


def log(msg: str) -> None:
    print(f"[demo] {msg}", flush=True)


def run(args, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, **kw)


def spawn(args, name: str, **kw) -> subprocess.Popen:
    p = subprocess.Popen(args, **kw)
    p.demo_name = name  # type: ignore[attr-defined]
    procs.append(p)
    return p


def as_user(user: str):
    import pwd

    pw = pwd.getpwnam(user)

    def drop():
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    return drop


def wait_http(url: str, seconds: int, proc: subprocess.Popen | None = None) -> None:
    end = time.time() + seconds
    while time.time() < end:
        if proc is not None and proc.poll() is not None:
            raise RuntimeError(f"it stopped (exit {proc.returncode}) before {url} answered")
        try:
            with urllib.request.urlopen(url, timeout=2):
                return
        except (urllib.error.URLError, OSError):
            time.sleep(0.5)
    raise RuntimeError(f"{url} did not answer in {seconds} s")


def call(port: int, method: str, path: str, token: str, body=None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
    req.add_header("authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("content-type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as r:
        text = r.read().decode()
    return json.loads(text) if text else {}


def start_postgres() -> None:
    if not (PG_DATA / "PG_VERSION").exists():
        PG_DATA.mkdir(parents=True, exist_ok=True)
        shutil.chown(PG_DATA, "postgres", "postgres")
        run([PG_BIN / "initdb", "-D", PG_DATA, "-U", "postgres", "--auth=trust", "-E", "UTF8",
             "--locale=C.UTF-8"], preexec_fn=as_user("postgres"), stdout=subprocess.DEVNULL)
    Path("/run/postgresql").mkdir(exist_ok=True)
    shutil.chown("/run/postgresql", "postgres", "postgres")
    spawn([PG_BIN / "postgres", "-D", PG_DATA, "-c", "listen_addresses=127.0.0.1",
           "-c", "max_connections=300", "-c", "fsync=off", "-c", "full_page_writes=off",
           "-c", "synchronous_commit=off"], "postgres", preexec_fn=as_user("postgres"))
    for _ in range(120):
        if subprocess.run([PG_BIN / "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-q"]).returncode == 0:
            return
        time.sleep(0.5)
    raise RuntimeError("PostgreSQL did not start")


def psql(sql: str) -> None:
    run([PG_BIN / "psql", "-h", "127.0.0.1", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q", "-c", sql],
        stdout=subprocess.DEVNULL)


def node_env(index: int, store: str, port: int) -> dict:
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/var/lib/iretail",
        "IRETAIL_ROLE": "store",
        "IRETAIL_LISTEN": f"127.0.0.1:{node_port(port)}",
        "DATABASE_URL": f"postgres://iretail_node@127.0.0.1:5432/{store.replace('-', '_')}",
        "REDIS_URL": f"redis://127.0.0.1:6379/{index}",
        "IRETAIL_GIFT_CARD_KEY_FILE": str(GIFT_KEY),
        "RUST_LOG": os.environ.get("RUST_LOG", "warn"),
    }
    if store == "pizzeria":
        env["IRETAIL_GUEST_LISTEN"] = "127.0.0.1:9188"
        env["IRETAIL_GUEST_ORIGIN"] = f"http://localhost:{GUEST_PORT}"
        env["IRETAIL_GUEST_TRUSTED_PROXIES"] = "127.0.0.1/32"
    return env


def node_port(port: int) -> int:
    return 9000 + port % 100 + 80  # 8081 -> 9161, ... 8087 -> 9167


def store_up(index: int, store: str, title: str, port: int, result: dict) -> None:
    db = store.replace("-", "_")
    psql(f"create database {db} owner iretail_node")
    pilot = json.loads((SRV / "pilots" / f"{store}.json").read_text(encoding="utf-8"))
    name = pilot["store"]["name"]["en"]
    env = node_env(index, store, port)
    init_env = dict(env, IRETAIL_INIT_ORG_NAME=f"{name} (demo)", IRETAIL_INIT_STORE_CODE=pilot["store"]["code"],
                    IRETAIL_INIT_STORE_NAME=name, IRETAIL_INIT_ADMIN_LOGIN=LOGIN, IRETAIL_INIT_ADMIN_PIN=PIN)
    out = run(["/usr/local/bin/node", "init"], env=init_env, preexec_fn=as_user("iretail"),
              capture_output=True, text=True).stdout
    office = out.strip().splitlines()[-1].strip()
    node = spawn(["/usr/local/bin/node", "serve"], f"node {store}", env=env, preexec_fn=as_user("iretail"))
    wait_http(f"http://127.0.0.1:{node_port(port)}/healthz", 120, node)
    load = subprocess.run(["python3", str(SRV / "load-pilot.py"), str(SRV / "pilots" / f"{store}.json"),
                           "--node", f"http://127.0.0.1:{node_port(port)}", "--login", LOGIN],
                          env=dict(os.environ, IRETAIL_DEVICE_TOKEN=office, IRETAIL_PIN=PIN),
                          capture_output=True, text=True)
    if load.returncode != 0:
        raise RuntimeError(f"{store}: loading the pilot failed: {load.stderr.strip()[-400:]}")
    session = call(node_port(port), "POST", "/v1/auth/login", office, {"login": LOGIN, "pin": PIN})["token"]
    register = call(node_port(port), "POST", "/v1/devices", session, {"kind": "register", "name": "Register 1"})["token"]
    result[store] = {"title": title, "name": name, "port": port, "office": office, "register": register}
    log(f"{name} is ready on http://localhost:{port}")


def start_devices() -> None:
    out = STATE / "receipts"
    out.mkdir(parents=True, exist_ok=True)
    spawn(["/usr/local/bin/emulator", "-unit", "lb", "-capacity", "30000", "-out", str(out),
           "-star-poll", "http://127.0.0.1:9444/cloudprnt/front", "-epson-poll", "http://127.0.0.1:9444/sdp/bar"],
          "emulators", env=dict(os.environ, EMULATOR_PRINTER_TOKEN="emulator"), stdout=subprocess.DEVNULL)
    spawn(["/usr/local/bin/gateway", "-config", str(SRV / "gateway.yaml")], "gateway",
          env=dict(os.environ, GATEWAY_TOKEN=GATEWAY_TOKEN, STRIPE_API_KEY="sk_test_emulator",
                   ADYEN_API_KEY="emulator", CLOVER_ACCESS_TOKEN="emulator", WORLDPAY_ACCOUNT_TOKEN="emulator",
                   FISERV_BOLT_KEY="emulator", FISERV_GATEWAY_PASSWORD="emulator",
                   EMULATOR_PRINTER_TOKEN="emulator"))


def nginx_conf(ready: dict) -> str:
    template = (SRV / "nginx.conf.template").read_text()
    servers = []
    for store, _title, port in STORES:
        if store not in ready:
            continue
        servers.append(template.replace("@PORT@", str(port)).replace("@NODE@", str(node_port(port))))
    guest = ""
    if "pizzeria" in ready:
        guest = f"""
  server {{
    listen {GUEST_PORT};
    location / {{
      proxy_pass http://127.0.0.1:9188;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $remote_addr;
    }}
  }}"""
    return (SRV / "nginx.conf").read_text().replace("@STORES@", "\n".join(servers) + guest)


def write_page(ready: dict, failed: dict, starting: bool) -> None:
    rows = []
    for store, title, port in STORES:
        if store in ready:
            s = ready[store]
            guest = ('<p>Guest menu: print the table cards in the back office (Restaurant, Table cards) '
                     f'and open a table\'s QR code; it is served on port {GUEST_PORT}.</p>'
                     if store == "pizzeria" else "")
            rows.append(f"""
      <article class="store">
        <h2>{html.escape(s['name'])} <span class="muted">· {html.escape(title)}</span></h2>
        <p class="actions">
          <a class="btn" href="http://localhost:{port}/">Back office in the browser</a>
          <a class="btn secondary" href="http://localhost:{port}/register/">Register in the browser</a>
        </p>
        <dl>
          <dt>Server address</dt><dd><code>http://localhost:{port}</code></dd>
          <dt>Back office device token</dt><dd><code class="tok">{html.escape(s['office'])}</code><button class="copy" type="button">Copy</button></dd>
          <dt>Register device token</dt><dd><code class="tok">{html.escape(s['register'])}</code><button class="copy" type="button">Copy</button></dd>
        </dl>{guest}
      </article>""")
        elif store in failed:
            rows.append(f'<article class="store"><h2>{html.escape(title)}</h2><p class="err">Did not start: '
                        f'{html.escape(failed[store])}</p></article>')
        elif starting:
            rows.append(f'<article class="store"><h2>{html.escape(title)}</h2><p class="muted">Starting…</p></article>')
    page = (SRV / "index.html").read_text()
    page = page.replace("@REFRESH@", '<meta http-equiv="refresh" content="5">' if starting else "")
    page = page.replace("@STATUS@", "Starting the stores, this takes a minute or two…" if starting else
                        "Ready. Everything here is invented and is gone when the container stops.")
    page = page.replace("@STORES@", "\n".join(rows)).replace("@PIN@", PIN).replace("@LOGIN@", LOGIN)
    page = page.replace("@GATEWAY_TOKEN@", GATEWAY_TOKEN).replace("@RELEASE_URL@", RELEASE_URL)
    tmp = WEB_ROOT / "index.html.tmp"
    tmp.write_text(page, encoding="utf-8")
    tmp.replace(WEB_ROOT / "index.html")


def reload_nginx(ready: dict) -> None:
    Path("/run/iretail-demo/nginx.conf").write_text(nginx_conf(ready))
    if not any(getattr(p, "demo_name", "") == "nginx" for p in procs):
        spawn(["nginx", "-c", "/run/iretail-demo/nginx.conf", "-g", "daemon off;"], "nginx")
    else:
        run(["nginx", "-c", "/run/iretail-demo/nginx.conf", "-s", "reload"])


def stop(*_):
    stopping.set()


def main() -> int:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    wanted = [s.strip() for s in os.environ.get("DEMO_STORES", "").split(",") if s.strip()]
    stores = [s for s in STORES if not wanted or s[0] in wanted]
    unknown = set(wanted) - {s[0] for s in STORES}
    if unknown:
        log(f"unknown in DEMO_STORES: {', '.join(sorted(unknown))}; the stores are "
            f"{', '.join(s[0] for s in STORES)}")
        return 2

    STATE.mkdir(parents=True, exist_ok=True)
    WEB_ROOT.mkdir(parents=True, exist_ok=True)
    GIFT_KEY.write_text(base64.b64encode(secrets.token_bytes(32)).decode())
    shutil.chown(GIFT_KEY, "iretail", "iretail")
    GIFT_KEY.chmod(0o400)

    ready: dict = {}
    failed: dict = {}
    write_page(ready, failed, True)
    reload_nginx(ready)
    log("start page on http://localhost:8080")

    spawn(["redis-server", "--save", "", "--appendonly", "no", "--bind", "127.0.0.1", "--databases", "16"],
          "redis", stdout=subprocess.DEVNULL)
    start_postgres()
    psql("create role iretail_node login createdb")
    start_devices()

    threads = []
    for index, (store, title, port) in enumerate(stores):
        def up(i=index, s=store, t=title, p=port):
            try:
                store_up(i, s, t, p, ready)
            except Exception as e:  # noqa: BLE001 — one store failing leaves the others running
                failed[s] = str(e)[:300]
                log(f"{s} did not start: {e}")
        t = threading.Thread(target=up)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    reload_nginx(ready)
    write_page(ready, failed, False)
    log(f"ready: {len(ready)} of {len(stores)} stores; open http://localhost:8080")
    if not ready:
        return 1

    while not stopping.is_set():
        for p in procs:
            if p.poll() is not None:
                log(f"{p.demo_name} stopped (exit {p.returncode}); stopping the demo")
                stopping.set()
                break
        stopping.wait(1)
    for p in reversed(procs):
        if p.poll() is None:
            p.terminate()
    for p in procs:
        try:
            p.wait(10)
        except subprocess.TimeoutExpired:
            p.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
