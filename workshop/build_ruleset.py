#!/usr/bin/env python3
"""Erzeugt einen Workshop-Regelsatz aus Rohdaten und einer Zuordnung.

Aufruf:
  python3 workshop/build_ruleset.py --mapping workshop/mapping/jinto_bg.json --out workshop/rulesets/jinto_bg

Bestehende Regelsätze werden nur mit --force überschrieben, weil der Web-Editor darin arbeitet.
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"

RARITIES = ["Common", "Uncommon", "Rare", "Super Rare", "Legendary"]
BG_KEYWORDS = {"TAUNT": "taunt", "DIVINE_SHIELD": "divine_shield", "REBORN": "reborn",
               "WINDFURY": "windfury", "VENOMOUS": "venomous", "STEALTH": "stealth"}
COLORS = {
    "rot": "#d9483b", "blau": "#3b6fd9", "gruen": "#3fa34d", "violett": "#8a4fd1", "grau": "#8c8c8c",
    "gold": "#d9a51e", "schwarz": "#2b2b2b", "tuerkis": "#2bb3b3", "braun": "#8b5a2b", "pink": "#e05a9c",
    "orange": "#e8862a",
}
COLOR_NAMES = {
    "rot": "Rot", "blau": "Blau", "gruen": "Grün", "violett": "Violett", "grau": "Grau", "gold": "Gold",
    "schwarz": "Schwarz", "tuerkis": "Türkis", "braun": "Braun", "pink": "Pink", "orange": "Orange",
}


def load_rows(path):
    return json.loads(path.read_text())["rows"]


def unit_name(rng, used):
    """Eigener Platzhaltername aus Silben, im Editor umbenennbar."""
    first = ["Bru", "Ka", "Mo", "Fi", "Lu", "Ze", "Ta", "No", "Ri", "Vo", "Pe", "Gra", "Sni", "Tu", "Wi", "Dra", "Kle", "Ba"]
    mid = ["", "ma", "li", "ro", "ne", "ku", "za", "pi", "lo"]
    last = ["bel", "mek", "rin", "dor", "lux", "pop", "zel", "fin", "tok", "sel", "gum", "bix", "ra", "wen"]
    while True:
        name = rng.choice(first) + rng.choice(mid) + rng.choice(last)
        if name not in used:
            used.add(name)
            return name


def ruleset_defaults(meta):
    bm = json.loads((RAW / "batomon" / "rules.json").read_text())
    odds = bm["shop"]["rarity_weights_by_rank"]
    ranks = sorted((k for k in odds if k[0].isdigit()), key=lambda k: int(k.rstrip("+")))
    return {
        "meta": {
            "name": meta.get("title", "Workshop"),
            "version": 1,
            "notes": "Erzeugt von workshop/build_ruleset.py. Werte mit Quelle in workshop/raw/SOURCES.md.",
        },
        "colors": [{"id": c, "name": COLOR_NAMES[c], "hex": h} for c, h in COLORS.items()],
        "rarities": RARITIES,
        "economy": {
            "income_by_day": [30, 35, 40, 55],
            "income_growth_after": 5,
            "income_note": "Tag 1 bis 4 beobachtet (ein Run), danach +5 pro Tag geschätzt.",
            "gold_carries_over": True,
            "reroll_cost": 3,
            "free_rerolls_per_day": 0,
            "sell_level_multiplier": [1, 3, 6],
            "sell_divisor": 2,
        },
        "shop": {
            "slots": 5,
            "rank_start": 1,
            "rank_per_day": 1,
            "rarity_weights_by_rank": [odds[k] for k in ranks],
            "exclude_owned_max_level": True,
        },
        "board": {"team_slots": 6, "bench_slots": 4, "max_level": 3, "merge_counts": [3, 2],
                  "merge_bonus": "max", "level_scale": [1, 2, 3]},
        "run": {
            "start_lives": 10, "wins_to_victory": 10, "max_days": 40,
            "life_loss_by_day": [1, 1, 2, 2, 3],
            "second_chance": True,
            "draw_result": "win",
        },
        "combat": {
            "mode": "bg",
            "bg": {"max_units": 7, "max_attacks": 200},
            "grid": {"cols": 3, "rows": 2, "max_ticks": 40},
        },
        "sim": {"ghosts_per_day": 60},
        "bots": {"max_actions_per_day": 60, "random_reroll_percent": 40, "greedy_reroll_min_gold": 13},
    }


def build(mapping_path, out_dir, force):
    mapping = json.loads(mapping_path.read_text())
    out_dir = Path(out_dir)
    if (out_dir / "units.json").exists() and not force:
        sys.exit(f"{out_dir} existiert schon. Mit --force überschreiben (Änderungen aus dem Editor gehen verloren).")

    slots = {m["id"]: m for m in load_rows(RAW / "batomon" / "monsters_index.json")}
    minions = {m["id"]: m for m in load_rows(RAW / "battlegrounds" / "minions.json")}
    type_colors = mapping["type_colors"]
    rng = random.Random(7)
    used = set()

    units, problems = [], []
    for i, entry in enumerate(mapping["units"], start=1):
        slot = slots.get(entry["slot"])
        bg = minions.get(entry["bg"])
        if slot is None or bg is None:
            problems.append(f"{entry['slot']} / {entry['bg']}: nicht in den Rohdaten")
            continue
        colors = [type_colors[t] for t in slot["types"] if t in type_colors]
        keywords = entry.get("keywords")
        if keywords is None:
            keywords = [BG_KEYWORDS[m] for m in bg["mechanics"] if m in BG_KEYWORDS]
        units.append({
            "id": f"u{i:02d}",
            "name": unit_name(rng, used),
            "rarity": RARITIES.index(slot["rarity"]),
            "cost": slot["cost"],
            "colors": colors,
            "atk": entry.get("atk", bg["attack"]),
            "hp": entry.get("hp", bg["health"]),
            "keywords": keywords,
            "passives": entry.get("passives", []),
            "abilities": entry.get("abilities", []),
            "status": entry.get("status", "ok"),
            "note": entry.get("note", ""),
            "ref": {
                "bg_id": bg["id"], "bg_name": bg["name"], "bg_tier": bg["tier"], "bg_text": bg["text"],
                "bg_races": bg["races"], "slot_id": slot["id"], "slot_name": slot["name"],
            },
        })
    if problems:
        sys.exit("Fehler in der Zuordnung:\n" + "\n".join(problems))

    ruleset = ruleset_defaults(mapping["meta"])
    sys.path.insert(0, str(HERE / "editor"))
    import validate
    problems = validate.check(ruleset, {"units": units, "tokens": mapping.get("tokens", [])})
    if problems:
        sys.exit("Regelsatz ungültig:\n" + "\n".join(problems))
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "ruleset.json").write_text(json.dumps(ruleset, ensure_ascii=False, indent=1) + "\n")
    (out_dir / "units.json").write_text(json.dumps(
        {"units": units, "tokens": mapping.get("tokens", [])}, ensure_ascii=False, indent=1) + "\n")

    by_rarity = [sum(1 for u in units if u["rarity"] == r) for r in range(len(RARITIES))]
    simplified = sum(1 for u in units if u["status"] != "ok")
    print(f"{out_dir}: {len(units)} Einheiten {by_rarity}, davon {simplified} vereinfacht, "
          f"{len(mapping.get('tokens', []))} Spielsteine")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--mapping", default=str(HERE / "mapping" / "jinto_bg.json"))
    ap.add_argument("--out", default=str(HERE / "rulesets" / "jinto_bg"))
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    build(Path(a.mapping), a.out, a.force)
