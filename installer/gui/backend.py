"""The back end of the graphical installer, in the live session of the ISO.

Like the installer of Fedora, the window only asks; this service knows the
computer and does the work. It listens on $SOCKET (one JSON object per line,
the protocol of the shell's other services: {"id", "method", "params"} in,
{"id", "result"} or {"id", "error"} back, {"event", "data"} unasked) and runs
the installer's core as root through sudo, with the answers and the secrets
in files only it and root can read.

Methods
  facts                 the computer: memory, disks, Secure Boot (strix-install --facts)
  timezones             the time zones of tzdata
  network               {online}: whether cache.nixos.org answers
  wifi.list             Wi-Fi networks NetworkManager sees
  wifi.connect          {ssid, password}
  install               {answers, password, passphrase}: starts the installation
  state                 where an installation stands, for a window opened later
  reboot

Events
  step {n, total}       a step of the core started
  line {text}           a line of its output
  done {ok, error, mokCode, mokFromDisk}
"""
import asyncio
import json
import os
import subprocess
import urllib.request

INSTALL = os.environ["INSTALL_COMMAND"]
SUDO = os.environ.get("SUDO", "/run/wrappers/bin/sudo")
NMCLI = os.environ.get("NMCLI", "nmcli")
SOCKET = os.environ["SOCKET"]
WORK = os.path.join(os.path.dirname(SOCKET), "install")

clients = set()
state = {"phase": "setup", "step": 0, "total": 9, "lines": [], "error": "", "mokCode": "", "mokFromDisk": False}
job = None


def emit(event, data):
    line = (json.dumps({"event": event, "data": data}) + "\n").encode()
    for writer in list(clients):
        try:
            writer.write(line)
        except Exception:
            clients.discard(writer)


def run(*args, timeout=30):
    out = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or out.stdout).strip().splitlines()[-1] if (out.stderr or out.stdout).strip() else "%s failed" % args[0])
    return out.stdout


def online():
    try:
        req = urllib.request.Request("https://cache.nixos.org/nix-cache-info", method="HEAD")
        urllib.request.urlopen(req, timeout=5)
        return True
    except Exception:
        return False


def wifi_list():
    out = run(NMCLI, "-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto")
    seen, nets = set(), []
    for line in out.splitlines():
        # nmcli -t escapes : inside fields as \:
        fields, cur, esc = [], "", False
        for ch in line:
            if esc:
                cur += ch
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == ":":
                fields.append(cur)
                cur = ""
            else:
                cur += ch
        fields.append(cur)
        if len(fields) < 4 or not fields[1] or fields[1] in seen:
            continue
        seen.add(fields[1])
        nets.append({"ssid": fields[1], "active": fields[0] == "*", "signal": int(fields[2] or 0),
                     "secure": fields[3] not in ("", "--")})
    nets.sort(key=lambda n: (not n["active"], -n["signal"]))
    return nets


def wifi_connect(params):
    args = [NMCLI, "device", "wifi", "connect", params["ssid"]]
    if params.get("password"):
        args += ["password", params["password"]]
    run(*args, timeout=60)
    return {"online": online()}


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)


async def install(params):
    global job
    if job is not None and state["phase"] == "installing":
        raise RuntimeError("An installation is already running.")
    os.makedirs(WORK, mode=0o700, exist_ok=True)
    answers, secrets = os.path.join(WORK, "answers.json"), os.path.join(WORK, "secrets.json")
    write_private(answers, params["answers"])
    write_private(secrets, {"password": params.get("password", ""), "passphrase": params.get("passphrase", "")})
    state.update(phase="installing", step=0, lines=[], error="", mokCode="", mokFromDisk=False)
    job = asyncio.create_task(watch(answers, secrets))
    return {"started": True}


async def watch(answers, secrets):
    proc = await asyncio.create_subprocess_exec(
        SUDO, "-n", INSTALL, "--core", "--answers", answers, "--secrets", secrets,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    error = ""
    async for raw in proc.stdout:
        text = raw.decode(errors="replace").rstrip("\n")
        if text.startswith("[") and "/" in text.split("]")[0]:
            try:
                n, total = text[1:text.index("]")].split("/")
                state["step"], state["total"] = int(n), int(total)
                emit("step", {"n": state["step"], "total": state["total"]})
                continue
            except ValueError:
                pass
        if text.startswith("MOK "):
            parts = text.split()
            state["mokCode"] = "" if parts[1] == "-" else parts[1]
            state["mokFromDisk"] = len(parts) > 2 and parts[2] == "1"
            continue
        if text.startswith("Error: "):
            error = text[len("Error: "):]
        state["lines"] = (state["lines"] + [text])[-300:]
        emit("line", {"text": text})
    code = await proc.wait()
    for leftover in (answers, secrets):
        if os.path.exists(leftover):
            os.remove(leftover)
    ok = code == 0
    if not ok and not error:
        error = "The installer stopped (exit %d)." % code
    state.update(phase="done" if ok else "failed", error=error)
    emit("done", {"ok": ok, "error": error, "mokCode": state["mokCode"], "mokFromDisk": state["mokFromDisk"]})


async def call(method, params):
    loop = asyncio.get_running_loop()
    blocking = lambda f, *a: loop.run_in_executor(None, f, *a)
    if method == "facts":
        return json.loads(await blocking(run, INSTALL, "--facts"))
    if method == "timezones":
        out = await blocking(run, "timedatectl", "list-timezones", "--no-pager")
        return [z for z in out.split() if "/" in z and not z.startswith(("Etc/", "SystemV/"))]
    if method == "network":
        return {"online": await blocking(online)}
    if method == "wifi.list":
        return await blocking(wifi_list)
    if method == "wifi.connect":
        return await blocking(wifi_connect, params)
    if method == "install":
        return await install(params)
    if method == "state":
        return state
    if method == "reboot":
        await blocking(run, "systemctl", "reboot")
        return {}
    raise RuntimeError("unknown method " + method)


async def serve(reader, writer):
    clients.add(writer)
    try:
        while line := await reader.readline():
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            try:
                result = await call(msg.get("method", ""), msg.get("params") or {})
                answer = {"id": msg.get("id"), "result": result}
            except Exception as e:
                answer = {"id": msg.get("id"), "error": str(e)}
            writer.write((json.dumps(answer) + "\n").encode())
            await writer.drain()
    finally:
        clients.discard(writer)
        writer.close()


async def main():
    os.makedirs(os.path.dirname(SOCKET), exist_ok=True)
    if os.path.exists(SOCKET):
        os.remove(SOCKET)
    server = await asyncio.start_unix_server(serve, path=SOCKET)
    os.chmod(SOCKET, 0o600)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
