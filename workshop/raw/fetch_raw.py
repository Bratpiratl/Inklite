#!/usr/bin/env python3
"""Lädt die Rohdaten für den Balancing-Workshop neu herunter.

Aufruf: python3 workshop/raw/fetch_raw.py
Schreibt nach workshop/raw/battlegrounds/ und workshop/raw/batomon/.
Die Regeln (rules.json) sind von Hand aus den Quellen in SOURCES.md übertragen
und werden hier nicht überschrieben.
"""
import gzip
import json
import re
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BG = ROOT / "battlegrounds"
BM = ROOT / "batomon"
UA = {"User-Agent": "inklite-balancing-workshop/1.0 (private research)"}

HSJSON = "https://api.hearthstonejson.com/v1/latest/enUS/cards.json"
FIRESTONE = "https://static.zerotoheroes.com/api/bgs/card-stats/mmr-{mmr}/{period}/overview-from-hourly.gz.json"
BATOMON_LIST = "https://batomon.com/batomon"
STEAM_NEWS = "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=4557380&count=200&maxlength=0"

# Völker, die in der aktuellen Saison nicht im Pool sind (Patch 36.6.1, 22.09.2026).
ROTATED_OUT = {"NAGA"}


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        return data, r.headers.get("Last-Modified")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write(path, meta, rows):
    path.write_text(json.dumps({"meta": meta, "rows": rows}, ensure_ascii=False, indent=1) + "\n")
    print(f"{path.relative_to(ROOT)}: {len(rows)} Einträge")


def clean_text(t):
    t = re.sub(r"<[^>]+>", "", t or "")
    t = t.replace("\n", " ").replace("[x]", "").replace("$", "")
    return re.sub(r"\s+", " ", t).strip()


def battlegrounds():
    raw, modified = fetch(HSJSON)
    cards = json.loads(raw)
    by_dbf = {c["dbfId"]: c for c in cards}
    minions, spells = [], []
    for c in cards:
        if c.get("isBattlegroundsPoolMinion"):
            races = c.get("races") or []
            golden = by_dbf.get(c.get("battlegroundsPremiumDbfId"), {})
            minions.append({
                "id": c["id"],
                "dbf_id": c["dbfId"],
                "name": c["name"],
                "tier": c.get("techLevel"),
                "attack": c.get("attack"),
                "health": c.get("health"),
                "races": races,
                "mechanics": c.get("mechanics", []),
                "text": clean_text(c.get("text")),
                "golden_attack": golden.get("attack"),
                "golden_health": golden.get("health"),
                "golden_text": clean_text(golden.get("text")),
                "duos_only": bool(c.get("isBattlegroundsDuosExclusive")),
                "rotated_out": bool(races) and all(r in ROTATED_OUT for r in races),
            })
        elif c.get("isBattlegroundsPoolSpell"):
            spells.append({
                "id": c["id"],
                "name": c["name"],
                "tier": c.get("techLevel"),
                "cost": c.get("cost"),
                "text": clean_text(c.get("text")),
                "duos_only": bool(c.get("isBattlegroundsDuosExclusive")),
            })
    minions.sort(key=lambda m: (m["tier"] or 0, m["name"]))
    spells.sort(key=lambda s: (s["tier"] or 0, s["name"]))
    meta = {"source": HSJSON, "source_last_modified": modified, "fetched": now(),
            "note": "Kartentexte und Namen gehören Blizzard. Nur für private Analyse."}
    write(BG / "minions.json", meta, minions)
    write(BG / "tavern_spells.json", meta, spells)

    ids = {m["id"] for m in minions}
    for mmr in (100, 50):
        raw, _ = fetch(FIRESTONE.format(mmr=mmr, period="last-patch"))
        d = json.loads(raw)
        rows = [{
            "id": s["cardId"],
            "games": s["totalPlayed"],
            "avg_placement": round(s["averagePlacement"], 3),
            "avg_placement_without": round(s["averagePlacementOther"], 3),
            "by_turn": [{"turn": t["turn"], "games": t["totalPlayed"],
                         "avg_placement": round(t["averagePlacement"], 3)}
                        for t in s.get("turnStats", [])],
        } for s in d["cardStats"] if s["cardId"] in ids]
        meta = {"source": FIRESTONE.format(mmr=mmr, period="last-patch"), "fetched": now(),
                "updated": d.get("lastUpdateDate"), "games_total": d.get("dataPoints"),
                "mmr_filter": "alle Spieler" if mmr == 100 else "obere 50 %",
                "note": "Durchschnittsplatz (1 bis 8) der Spiele, in denen der Diener gespielt wurde. "
                        "avg_placement_without: Spiele ohne ihn. Daten der Firestone-Nutzer."}
        write(BG / f"stats_mmr{mmr}.json", meta, rows)
        time.sleep(1)


def batomon():
    raw, _ = fetch(BATOMON_LIST)
    html = raw.decode("utf-8")
    chunks = re.findall(r'self\.__next_f\.push\((\[1,".*?"\])\)</script>', html, flags=re.S)
    payload = "".join(json.loads(c)[1] for c in chunks)
    pattern = re.compile(
        r'"version":\{"steamBuild":"(\d+)","balanceVersion":(\d+).*?'
        r'"id":"([^"]+)","kind":"batomon","slug":"[^"]+","name":"([^"]+)",'
        r'"description":"((?:[^"\\]|\\.)*)".*?"tier":(\d+),"types":(\[[^\]]*\]),'
        r'"cost":(\d+),"regions":(\[[^\]]*\]).*?"chips":\[\{"label":"([^"]+)"')
    rows, seen, build = [], set(), None
    for m in pattern.finditer(payload):
        if m[3] in seen:
            continue
        seen.add(m[3])
        build = f"Steam {m[1]}, balance {m[2]}"
        rows.append({
            "id": m[3], "name": m[4], "rarity": m[10], "rarity_tier": int(m[6]),
            "cost": int(m[8]), "types": json.loads(m[7]), "regions": json.loads(m[9]),
            "ability_lv1": json.loads('"' + m[5] + '"'),
        })
    rows.sort(key=lambda r: (r["rarity_tier"], r["cost"], r["name"]))
    meta = {"source": BATOMON_LIST, "fetched": now(), "game_build": build,
            "note": "Community-Seite mit Daten aus dem Steam-Build. Nur Seltenheit, Preis, Typen "
                    "und Fähigkeit auf Stufe 1. Namen gehören berrymint."}
    write(BM / "monsters_index.json", meta, rows)

    raw, _ = fetch(STEAM_NEWS)
    news = json.loads(raw)["appnews"]["newsitems"]
    out = [f"Offizielle Steam-Ankündigungen von Batomon Showdown, geladen {now()}", f"Quelle: {STEAM_NEWS}", ""]
    for n in sorted(news, key=lambda n: n["date"]):
        day = datetime.fromtimestamp(n["date"], timezone.utc).strftime("%Y-%m-%d")
        body = re.sub(r"\[/(p|h\d)\]", "\n", n["contents"])
        body = re.sub(r"\[/?(p|b|i|list|h\d|url[^\]]*|dynamiclink[^\]]*|img[^\]]*)\]", "", body)
        body = re.sub(r"\[\*\]", "\n- ", body).replace("[/*]", "")
        out += [f"===== {day} | {n['title']}", n["url"], re.sub(r"\n{3,}", "\n\n", body).strip(), ""]
    (BM / "patch_notes.txt").write_text("\n".join(out) + "\n")
    print(f"batomon/patch_notes.txt: {len(news)} Ankündigungen")


if __name__ == "__main__":
    BG.mkdir(exist_ok=True)
    BM.mkdir(exist_ok=True)
    battlegrounds()
    batomon()
