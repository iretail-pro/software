#!/usr/bin/env bash
# Starts a demo image (demo.yml) and checks every store it serves: the start
# page lists it ready, its back office and register pages load from its port,
# the back office's device token and the demo's PIN sign in, its catalog has
# items, and the register's token signs in too. Stops the container after.
#
#   scripts/demo-test.sh <image>
#
# Needs docker, curl and python3.
set -euo pipefail
image="${1:?usage: demo-test.sh <image>}"
name="demo-test-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p 127.0.0.1:18080-18088:8080-8088 "$image" >/dev/null
for _ in $(seq 1 180); do
  if docker logs "$name" 2>&1 | grep -q '^\[demo\] ready:'; then break; fi
  if ! docker inspect -f '{{.State.Running}}' "$name" | grep -q true; then break; fi
  sleep 2
done
docker logs "$name" 2>&1 | grep '^\[demo\]' || true
docker logs "$name" 2>&1 | grep -q '^\[demo\] ready: 7 of 7 stores' || { echo "demo-test: not every store started" >&2; exit 1; }
python3 - <<'EOF'
import json, re, urllib.request

def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.status, r.read().decode()

_, page = get("http://127.0.0.1:18080/")
pin = re.search(r"PIN <code>(\d+)</code>", page).group(1)
tokens = re.findall(r'<code class="tok">([^<]+)</code>', page)
assert len(tokens) == 14, f"the start page lists {len(tokens)} tokens, not 14"
for i in range(7):
    port = 18081 + i
    def call(method, path, token, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
        req.add_header("authorization", f"Bearer {token}")
        req.add_header("content-type", "application/json")
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    assert get(f"http://127.0.0.1:{port}/")[0] == 200
    assert '<base href="/register/">' in get(f"http://127.0.0.1:{port}/register/")[1]
    office, register = tokens[2 * i], tokens[2 * i + 1]
    session = call("POST", "/v1/auth/login", office, {"login": "admin", "pin": pin})["token"]
    items = call("GET", "/v1/items?limit=200", session)
    rows = items["items"] if isinstance(items, dict) else items
    assert rows, f"port {port}: no items"
    name = call("GET", "/v1/store", session)["name"]["en"]
    call("POST", "/v1/auth/login", register, {"login": "admin", "pin": pin})
    print(f"demo-test: {name}: {len(rows)} items, back office and register sign in")
EOF
