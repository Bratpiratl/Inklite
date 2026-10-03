#!/usr/bin/env python3
"""Web-Editor für den Balancing-Workshop. Nur Python-Standardbibliothek.

Start (aus dem Repo-Root):  python3 workshop/editor/server.py [--port 8741]
Zugang: Basic Auth, Benutzer und Passwort in workshop/editor/config.local.json (nicht im Repo).
Lauscht nur auf 127.0.0.1; öffentlich über nginx unter /inklite-workshop/.

Ablauf beim Üben: Werte ändern -> Speichern mit Notiz und Vorhersage -> Simulation starten ->
Ergebnis mit dem Lauf davor vergleichen -> Ergebnis zur Vorhersage eintragen.
"""
import argparse
import base64
import hmac
import json
import mimetypes
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
WORKSHOP = HERE.parent
REPO = WORKSHOP.parent
RULESETS = WORKSHOP / "rulesets"
RUNS = WORKSHOP / "runs"
STATIC = HERE / "static"
CONFIG = HERE / "config.local.json"
PYTHON = REPO / "analysis" / ".venv" / "bin" / "python"
NAME_RE = re.compile(r"^[a-z0-9_\-]{1,40}$")

sys.path.insert(0, str(HERE))
import validate  # noqa: E402


def now_id():
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def write_json(path, data):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def load_config():
    cfg = read_json(CONFIG)
    if not cfg:
        cfg = {"user": "bastian", "password": secrets.token_urlsafe(12)}
        write_json(CONFIG, cfg)
        CONFIG.chmod(0o600)
        print(f"Neue Zugangsdaten in {CONFIG}: Benutzer {cfg['user']}, Passwort {cfg['password']}")
    return cfg


def ruleset_dir(name):
    if not NAME_RE.match(name or ""):
        raise ValueError("Ungültiger Name")
    return RULESETS / name


def diff_summary(old, new):
    """Kurze Liste der Änderungen zwischen zwei Ständen (Einheiten und Regeln)."""
    changes = []
    old_units = {u["id"]: u for u in old.get("units", {}).get("units", [])}
    for u in new.get("units", {}).get("units", []):
        before = old_units.get(u["id"])
        if before is None:
            changes.append(f"{u['id']} neu")
            continue
        for key in ["name", "rarity", "cost", "colors", "atk", "hp", "keywords", "passives", "abilities", "disabled"]:
            if before.get(key) != u.get(key):
                if key in ("abilities",):
                    changes.append(f"{u['id']} {u.get('name', '')}: Fähigkeiten geändert")
                else:
                    changes.append(f"{u['id']} {u.get('name', '')}: {key} {json.dumps(before.get(key), ensure_ascii=False)} → {json.dumps(u.get(key), ensure_ascii=False)}")
    old_rules = old.get("ruleset", {})
    for section, values in new.get("ruleset", {}).items():
        if section == "meta":
            continue
        if old_rules.get(section) != values:
            if isinstance(values, dict):
                for k, v in values.items():
                    if (old_rules.get(section) or {}).get(k) != v:
                        changes.append(f"{section}.{k}: {json.dumps((old_rules.get(section) or {}).get(k), ensure_ascii=False)} → {json.dumps(v, ensure_ascii=False)}")
            else:
                changes.append(f"{section} geändert")
    return changes


class Jobs:
    """Höchstens eine Simulation gleichzeitig, der Server ist klein."""

    def __init__(self):
        self.lock = threading.Lock()
        self.current = None

    def status(self):
        with self.lock:
            return dict(self.current) if self.current else None

    def start(self, name, params):
        with self.lock:
            if self.current and self.current["state"] == "läuft":
                raise RuntimeError("Es läuft schon eine Simulation")
            run_id = now_id()
            self.current = {"ruleset": name, "run": run_id, "state": "läuft", "step": "Start", "log": [],
                            "started": time.time(), "params": params}
        threading.Thread(target=self._run, args=(name, run_id, params), daemon=True).start()
        return run_id

    def _set(self, **kw):
        with self.lock:
            self.current.update(kw)

    def _log(self, line):
        with self.lock:
            self.current["log"] = (self.current["log"] + [line])[-60:]

    def _exec(self, cmd):
        proc = subprocess.Popen(cmd, cwd=str(REPO), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            line = line.rstrip()
            if line and not line.startswith(("Godot Engine", "WARNING: ObjectDB", "     at:", "ERROR: 1 resources", "   at:")):
                self._log(line)
        return proc.wait()

    def _run(self, name, run_id, params):
        out_dir = RUNS / name / run_id
        out_dir.mkdir(parents=True, exist_ok=True)
        rs_rel = f"workshop/rulesets/{name}"
        log_rel = f"workshop/runs/{name}/{run_id}/sim.jsonl"
        try:
            meta = {"run": run_id, "ruleset": name, "params": params, "started": datetime.now().isoformat(timespec="seconds"),
                    "version": (read_json(RULESETS / name / "ruleset.json", {}) or {}).get("meta", {}).get("version"),
                    "change": (read_changelog(name) or [{}])[-1].get("id")}
            write_json(out_dir / "meta.json", meta)
            shutil.copy(RULESETS / name / "ruleset.json", out_dir / "ruleset.json")
            shutil.copy(RULESETS / name / "units.json", out_dir / "units.json")
            cmd = ["godot", "--headless", "--path", "game", "-s", "res://tools/ws_simulate.gd", "--",
                   "--ruleset", rs_rel, "--runs", str(params["runs"]), "--seed", str(params["seed"]),
                   "--ghosts", str(params["ghosts"]), "--out", log_rel]
            if params.get("combat"):
                cmd += ["--combat", params["combat"]]
            self._set(step="Simulation (Bots spielen Runs)")
            if self._exec(cmd) != 0:
                raise RuntimeError("Simulation fehlgeschlagen")
            self._set(step="Auswertung")
            if self._exec([str(PYTHON), "workshop/analysis/ws_analyze.py", log_rel, "--ruleset", rs_rel,
                           "--out-dir", f"workshop/runs/{name}/{run_id}"]) != 0:
                raise RuntimeError("Auswertung fehlgeschlagen")
            # Das große Log wird nicht mehr gebraucht, die Zusammenfassung reicht.
            if not params.get("keep_log"):
                (out_dir / "sim.jsonl").unlink(missing_ok=True)
            meta["finished"] = datetime.now().isoformat(timespec="seconds")
            write_json(out_dir / "meta.json", meta)
            self._set(state="fertig", step="Fertig")
        except Exception as e:  # noqa: BLE001
            self._log(f"FEHLER: {e}")
            self._set(state="fehler", step=str(e))


def read_changelog(name):
    path = RULESETS / name / "changelog.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_changelog(name, entries):
    path = RULESETS / name / "changelog.jsonl"
    path.write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in entries), encoding="utf-8")


JOBS = Jobs()
CFG = {}


class Handler(BaseHTTPRequestHandler):
    server_version = "InkliteWorkshop/1"

    def log_message(self, fmt, *args):
        pass

    # --- Hilfen ---

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            user, _, pw = base64.b64decode(header[6:]).decode("utf-8").partition(":")
        except (ValueError, UnicodeDecodeError):
            return False
        return hmac.compare_digest(user, CFG["user"]) and hmac.compare_digest(pw, CFG["password"])

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.end_headers()
        self.wfile.write(data)

    def _error(self, code, msg):
        self._send(code, {"error": msg})

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n > 5_000_000:
            raise ValueError("Anfrage zu groß")
        return json.loads(self.rfile.read(n) or b"{}")

    def _route(self):
        path = unquote(urlparse(self.path).path)
        # Hinter nginx kommt der Präfix /inklite-workshop/ mit, lokal nicht.
        if path.startswith("/inklite-workshop"):
            path = path[len("/inklite-workshop"):] or "/"
        return [p for p in path.split("/") if p]

    def _guard(self):
        if not self._authorized():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Inklite Workshop", charset="UTF-8"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False
        return True

    # --- Verben ---

    def do_GET(self):
        if not self._guard():
            return
        parts = self._route()
        try:
            if not parts or parts[0] in ("index.html",):
                return self._static("index.html")
            if parts[0] == "static":
                return self._static("/".join(parts[1:]))
            if parts[0] == "runs" and len(parts) == 4 and parts[3] == "report.html":
                ruleset_dir(parts[1])
                if not re.match(r"^\d{8}-\d{6}$", parts[2]):
                    return self._error(404, "Nicht gefunden")
                f = RUNS / parts[1] / parts[2] / "report.html"
                return self._send(200, f.read_bytes(), "text/html; charset=utf-8") if f.exists() else self._error(404, "Kein Bericht")
            if parts[0] != "api":
                return self._error(404, "Nicht gefunden")
            return self._api_get(parts[1:])
        except ValueError as e:
            self._error(400, str(e))

    def do_PUT(self):
        self.do_POST()

    def do_POST(self):
        if not self._guard():
            return
        parts = self._route()
        if not parts or parts[0] != "api":
            return self._error(404, "Nicht gefunden")
        try:
            return self._api_post(parts[1:], self._body())
        except (ValueError, RuntimeError) as e:
            self._error(400, str(e))

    def _static(self, rel):
        f = (STATIC / rel).resolve()
        if not str(f).startswith(str(STATIC.resolve())) or not f.is_file():
            return self._error(404, "Nicht gefunden")
        ctype = mimetypes.guess_type(str(f))[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/javascript",):
            ctype += "; charset=utf-8"
        self._send(200, f.read_bytes(), ctype)

    # --- API ---

    def _api_get(self, p):
        if p == ["rulesets"]:
            names = sorted(d.name for d in RULESETS.iterdir() if (d / "units.json").exists()) if RULESETS.exists() else []
            return self._send(200, {"rulesets": names})
        if len(p) == 2 and p[0] == "ruleset":
            d = ruleset_dir(p[1])
            return self._send(200, {"name": p[1], "ruleset": read_json(d / "ruleset.json"), "units": read_json(d / "units.json"),
                                    "has_ghosts": (d / "ghosts.json").exists(), "schema": validate.SCHEMA})
        if len(p) == 2 and p[0] == "changelog":
            ruleset_dir(p[1])
            return self._send(200, {"entries": read_changelog(p[1])})
        if len(p) == 2 and p[0] == "runs":
            ruleset_dir(p[1])
            runs = []
            base = RUNS / p[1]
            if base.exists():
                for d in sorted(base.iterdir(), reverse=True):
                    meta = read_json(d / "meta.json")
                    summary = read_json(d / "summary.json")
                    if not meta:
                        continue
                    runs.append({"run": d.name, "meta": meta,
                                 "overall": (summary or {}).get("overall"), "groups": (summary or {}).get("groups"),
                                 "has_report": (d / "report.html").exists()})
            return self._send(200, {"runs": runs})
        if len(p) == 3 and p[0] == "run":
            ruleset_dir(p[1])
            if not re.match(r"^\d{8}-\d{6}$", p[2]):
                return self._error(404, "Nicht gefunden")
            summary = read_json(RUNS / p[1] / p[2] / "summary.json")
            return self._send(200, summary) if summary else self._error(404, "Keine Auswertung")
        if p == ["job"]:
            return self._send(200, {"job": JOBS.status()})
        return self._error(404, "Unbekannt")

    def _api_post(self, p, body):
        if len(p) == 2 and p[0] == "ruleset":
            d = ruleset_dir(p[1])
            if not d.exists():
                raise ValueError("Regelsatz fehlt")
            new = {"ruleset": body.get("ruleset"), "units": body.get("units")}
            problems = validate.check(new["ruleset"], new["units"])
            if problems:
                return self._send(422, {"error": "Ungültige Daten", "problems": problems})
            old = {"ruleset": read_json(d / "ruleset.json", {}), "units": read_json(d / "units.json", {})}
            changes = diff_summary(old, new)
            if not changes:
                return self._send(200, {"ok": True, "changes": []})
            entry_id = now_id()
            hist = d / "history"
            hist.mkdir(exist_ok=True)
            write_json(hist / f"{entry_id}.json", old)
            meta = new["ruleset"].setdefault("meta", {})
            meta["version"] = int(meta.get("version", 1)) + 1
            write_json(d / "ruleset.json", new["ruleset"])
            write_json(d / "units.json", new["units"])
            entries = read_changelog(p[1])
            entries.append({"id": entry_id, "version": meta["version"], "note": body.get("note", ""),
                            "prediction": body.get("prediction", ""), "result": "", "changes": changes})
            write_changelog(p[1], entries)
            return self._send(200, {"ok": True, "changes": changes, "version": meta["version"]})
        if len(p) == 3 and p[0] == "ruleset" and p[2] == "copy":
            src = ruleset_dir(p[1])
            dst = ruleset_dir(body.get("name", ""))
            if dst.exists():
                raise ValueError("Name schon vergeben")
            dst.mkdir(parents=True)
            for f in ("ruleset.json", "units.json", "ghosts.json"):
                if (src / f).exists():
                    shutil.copy(src / f, dst / f)
            return self._send(200, {"ok": True, "name": dst.name})
        if len(p) == 3 and p[0] == "changelog" and p[2] == "result":
            ruleset_dir(p[1])
            entries = read_changelog(p[1])
            for e in entries:
                if e["id"] == body.get("id"):
                    e["result"] = body.get("result", "")
            write_changelog(p[1], entries)
            return self._send(200, {"ok": True})
        if len(p) == 3 and p[0] == "changelog" and p[2] == "restore":
            d = ruleset_dir(p[1])
            snap = read_json(d / "history" / f"{body.get('id', '')}.json") if re.match(r"^\d{8}-\d{6}$", body.get("id", "")) else None
            if not snap:
                raise ValueError("Stand nicht gefunden")
            current_version = (read_json(d / "ruleset.json", {}) or {}).get("meta", {}).get("version", 1)
            return self._api_post(["ruleset", p[1]], {
                "ruleset": dict(snap["ruleset"], meta=dict(snap["ruleset"].get("meta", {}), version=current_version)),
                "units": snap["units"], "note": f"Zurück auf den Stand vor {body['id']}", "prediction": ""})
        if len(p) == 2 and p[0] == "simulate":
            ruleset_dir(p[1])
            params = {"runs": max(30, min(int(body.get("runs", 900)), 20000)),
                      "ghosts": max(0, min(int(body.get("ghosts", 2)), 5)),
                      "seed": int(body.get("seed", 1)),
                      "combat": body.get("combat") if body.get("combat") in ("bg", "grid") else "",
                      "keep_log": bool(body.get("keep_log", False))}
            run_id = JOBS.start(p[1], params)
            return self._send(200, {"ok": True, "run": run_id})
        return self._error(404, "Unbekannt")


def main():
    global CFG
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8741)
    ap.add_argument("--host", default="127.0.0.1")
    a = ap.parse_args()
    CFG = load_config()
    RUNS.mkdir(parents=True, exist_ok=True)
    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print(f"Workshop-Editor auf http://{a.host}:{a.port}/")
    srv.serve_forever()


if __name__ == "__main__":
    main()
