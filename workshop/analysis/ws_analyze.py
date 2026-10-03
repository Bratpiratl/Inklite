"""Wertet ein Workshop-Log (game/tools/ws_simulate.gd) aus.

Aufruf (aus dem Repo-Root):
    analysis/.venv/bin/python workshop/analysis/ws_analyze.py workshop/runs/jinto_bg/sim.jsonl \
        --ruleset workshop/rulesets/jinto_bg [--out-dir workshop/runs/jinto_bg]

Schreibt summary.json (für den Editor) und report.html.

Winrates werden je Tag bereinigt: Abstand zum Schnitt aller Kämpfe desselben Tages, plus 50.
Sonst sehen Einheiten, die erst spät auftauchen, besser aus, nur weil starke Teams länger leben.
Unentschieden zählen als halber Sieg, unabhängig davon, wie der Run sie wertet.
"""

import argparse
import base64
import html
import io
import json
from datetime import datetime
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

# Warnung, wenn eine Einheit so weit vom Schnitt ihrer Seltenheit abweicht. Höhere Seltenheit darf
# stärker sein, sie kostet mehr; verglichen wird deshalb innerhalb der Seltenheit.
RARITY_GAP = 8.0
MIN_SAMPLES = 80
PHASES = [("früh", 1, 3), ("mitte", 4, 7), ("spät", 8, 99)]
RARITY_NAMES = ["Common", "Uncommon", "Rare", "Super Rare", "Legendary"]
REPO = Path(__file__).resolve().parents[2]


def load_log(path: Path) -> pd.DataFrame:
    rows = [json.loads(line) for line in path.open(encoding="utf-8") if line.strip()]
    if not rows:
        raise SystemExit(f"Keine Ereignisse in {path}")
    return pd.DataFrame(rows)


def score(row) -> float:
    winner = row.get("winner")
    if winner is None or pd.isna(winner):
        return {"win": 1.0, "draw": 0.5, "loss": 0.0}[row["result"]]
    return 1.0 if winner == 0 else (0.0 if winner == 1 else 0.5)


def spearman(a: pd.Series, b: pd.Series) -> float:
    if len(a) < 3:
        return float("nan")
    return float(a.rank().corr(b.rank()))


def load_bg_stats() -> dict:
    path = REPO / "workshop" / "raw" / "battlegrounds" / "stats_mmr100.json"
    if not path.exists():
        return {}
    return {r["id"]: r for r in json.loads(path.read_text())["rows"]}


def load_ghost_strength(ruleset_dir) -> dict:
    """Durchschnittliche Teamstärke der Geisterteams, in denen eine Einheit steht (zweite Messgröße)."""
    path = Path(ruleset_dir) / "ghosts.json" if ruleset_dir else None
    if not path or not path.exists():
        return {}
    sums, counts = {}, {}
    for g in json.loads(path.read_text()).get("teams", []):
        if "strength" not in g:
            continue
        for uid in {e["id"] for e in g.get("team", [])}:
            sums[uid] = sums.get(uid, 0) + g["strength"]
            counts[uid] = counts.get(uid, 0) + 1
    return {u: round(sums[u] / counts[u], 1) for u in sums if counts[u] >= 10}


def analyze(df: pd.DataFrame, units: dict, ruleset_dir=None) -> dict:
    battles = df[df["ev"] == "battle"].copy()
    shops = df[df["ev"] == "shop"].copy()
    ends = df[df["ev"] == "run_end"].copy()
    battles["score"] = battles.apply(score, axis=1)
    baseline = battles.groupby("day")["score"].mean()
    battles["adj"] = battles["score"] - battles["day"].map(baseline)

    # Je Kampf zählt jede Einheit einmal, egal wie oft und auf welcher Stufe.
    rows = []
    for b in battles.itertuples():
        seen = {}
        for tag in b.team:
            uid, level = tag.split(":")
            seen[uid] = max(seen.get(uid, 0), int(level))
        for uid, level in seen.items():
            rows.append((uid, b.day, b.adj, level, b.bot))
    presence = pd.DataFrame(rows, columns=["id", "day", "adj", "level", "bot"])

    # Schaden je Einheit aus unit_stats (Beschwörungen sind der Beschwörerin zugerechnet).
    # carry: In gewonnenen Kämpfen die Einheit mit dem meisten Schaden im Team.
    dmg_rows = []
    if "unit_stats" in battles:
        for b in battles.itertuples():
            stats = b.unit_stats if isinstance(b.unit_stats, list) else []
            total = sum(s[1] for s in stats)
            top = max((s[1] for s in stats), default=0)
            for tag, dmg, kills, taken in stats:
                dmg_rows.append((tag.split(":")[0], dmg, kills, taken, dmg / total if total else 0.0,
                                 b.score == 1.0 and dmg == top and top > 0, b.score == 1.0))
    dmg = pd.DataFrame(dmg_rows, columns=["id", "damage", "kills", "taken", "share", "carry", "won"])

    offered = shops.explode("offered").groupby("offered").size()
    bought = shops.explode("bought").dropna(subset=["bought"]).groupby("bought").size()
    n_battles = len(battles)
    bg = load_bg_stats()
    ghost_strength = load_ghost_strength(ruleset_dir)

    unit_rows = []
    for uid, d in units.items():
        p = presence[presence["id"] == uid]
        row = {
            "id": uid, "name": d.get("name", uid), "rarity": d.get("rarity", 0), "cost": d.get("cost", 0),
            "colors": d.get("colors", []), "status": d.get("status", ""),
            "offered": int(offered.get(uid, 0)), "bought": int(bought.get(uid, 0)),
            "battles": int(len(p)),
            "presence": round(100.0 * len(p) / max(n_battles, 1), 1),
            "winrate": round(50.0 + 100.0 * p["adj"].mean(), 1) if len(p) else None,
            "level3_share": round(100.0 * (p["level"] >= 3).mean(), 1) if len(p) else None,
        }
        row["pick_rate"] = round(100.0 * row["bought"] / row["offered"], 1) if row["offered"] else None
        for name, lo, hi in PHASES:
            q = p[(p["day"] >= lo) & (p["day"] <= hi)]
            row["winrate_" + name] = round(50.0 + 100.0 * q["adj"].mean(), 1) if len(q) >= 20 else None
        row["ghost_strength"] = ghost_strength.get(uid)
        dq = dmg[dmg["id"] == uid] if len(dmg) else dmg
        row["avg_damage"] = round(float(dq["damage"].mean()), 1) if len(dq) else None
        row["avg_kills"] = round(float(dq["kills"].mean()), 2) if len(dq) else None
        row["damage_share"] = round(100.0 * float(dq["share"].mean()), 1) if len(dq) else None
        won = dq[dq["won"]] if len(dq) else dq
        row["carry_rate"] = round(100.0 * float(won["carry"].mean()), 1) if len(won) >= 20 else None
        ref = d.get("ref", {})
        row["bg_name"] = ref.get("bg_name", "")
        stat = bg.get(ref.get("bg_id", ""))
        row["bg_avg_placement"] = stat["avg_placement"] if stat else None
        unit_rows.append(row)

    # Schnitt je Seltenheit über Einheiten mit genug Kämpfen, dann Abweichung und Warnung.
    means = {}
    for r in {u["rarity"] for u in unit_rows}:
        vals = [u["winrate"] for u in unit_rows if u["rarity"] == r and u["winrate"] is not None and u["battles"] >= MIN_SAMPLES]
        means[r] = sum(vals) / len(vals) if vals else None
    for u in unit_rows:
        m = means.get(u["rarity"])
        u["vs_rarity"] = round(u["winrate"] - m, 1) if u["winrate"] is not None and m is not None else None
        u["flag"] = ""
        if u["vs_rarity"] is not None and u["battles"] >= MIN_SAMPLES:
            if u["vs_rarity"] > RARITY_GAP:
                u["flag"] = "stark"
            elif u["vs_rarity"] < -RARITY_GAP:
                u["flag"] = "schwach"
    udf = pd.DataFrame(unit_rows)

    groups = {}
    ends["bot"] = ends["bot"].fillna("spieler")
    for bot, e in list(ends.groupby("bot")) + [("alle", ends)]:
        hist = e["wins"].value_counts().sort_index()
        groups[bot] = {
            "runs": int(len(e)), "avg_wins": round(float(e["wins"].mean()), 2),
            "victory_rate": round(100.0 * float(e["victory"].mean()), 1),
            "avg_days": round(float(e["days"].mean()), 1),
            "wins_hist": {int(k): int(v) for k, v in hist.items()},
        }

    days = []
    for day, g in battles.groupby("day"):
        days.append({"day": int(day), "battles": int(len(g)), "winrate": round(100.0 * g["score"].mean(), 1),
                     "avg_attacks": round(float(g["attacks"].mean()), 1),
                     "gold_left": round(float(g["gold_left"].mean()), 1) if "gold_left" in g else None})

    colors = []
    for c in sorted({c for d in units.values() for c in d.get("colors", [])}):
        mask = battles["team"].apply(lambda team: sum(1 for t in team if c in units.get(t.split(":")[0], {}).get("colors", [])) >= 3)
        sub = battles[mask]
        colors.append({"color": c, "battles": int(len(sub)),
                       "share": round(100.0 * len(sub) / max(n_battles, 1), 1),
                       "winrate": round(50.0 + 100.0 * sub["adj"].mean(), 1) if len(sub) >= 20 else None})

    rarity = []
    for r, g in udf.dropna(subset=["winrate"]).groupby("rarity"):
        rarity.append({"rarity": int(r), "name": RARITY_NAMES[int(r)] if int(r) < len(RARITY_NAMES) else str(r),
                       "units": int(len(g)), "winrate_mean": round(float(g["winrate"].mean()), 1),
                       "winrate_spread": round(float(g["winrate"].std()), 1) if len(g) > 1 else 0.0})

    valid = udf.dropna(subset=["winrate", "bg_avg_placement"])
    valid = valid[valid["battles"] >= MIN_SAMPLES]
    compare = {"n": int(len(valid)),
               "spearman": round(spearman(valid["winrate"], -valid["bg_avg_placement"]), 2) if len(valid) >= 3 else None}

    draws = battles["winner"].eq(-1).mean() if "winner" in battles else 0.0
    return {
        "generated": datetime.now().isoformat(timespec="seconds"),
        "overall": {"runs": int(len(ends)), "battles": int(n_battles), "draw_rate": round(100.0 * float(draws), 1),
                    "avg_attacks": round(float(battles["attacks"].mean()), 1)},
        "groups": groups, "days": days, "units": unit_rows, "colors": colors, "rarity": rarity, "bg_compare": compare,
    }


# --- Bericht ---

def chart(fig) -> str:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight")
    plt.close(fig)
    return '<img alt="Diagramm" src="data:image/png;base64,%s">' % base64.b64encode(buf.getvalue()).decode()


def table(rows, columns, fmt=None) -> str:
    fmt = fmt or {}
    head = "".join(f"<th>{html.escape(label)}</th>" for _, label in columns)
    body = []
    for r in rows:
        cells = []
        for key, _ in columns:
            v = r.get(key)
            if callable(fmt.get(key)):
                v = fmt[key](v, r)
            elif isinstance(v, float):
                v = f"{v:.1f}"
            elif isinstance(v, list):
                v = ", ".join(map(str, v))
            cells.append(f"<td>{'' if v is None else html.escape(str(v))}</td>")
        cls = ' class="flag-%s"' % r.get("flag") if r.get("flag") else ""
        body.append(f"<tr{cls}>{''.join(cells)}</tr>")
    return f"<table><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table>"


def report(summary: dict, source: str, ruleset_name: str, combat: str) -> str:
    units = sorted([u for u in summary["units"] if u["winrate"] is not None], key=lambda u: -u["winrate"])
    parts = [f"<h1>Workshop-Bericht: {html.escape(ruleset_name)}</h1>",
             f"<p class=meta>Log: {html.escape(source)} · Kampf: {html.escape(combat)} · erstellt {summary['generated']}</p>"]

    o = summary["overall"]
    parts.append(f"<p>{o['runs']} Runs, {o['battles']} Kämpfe, Unentschieden {o['draw_rate']} %, "
                 f"im Schnitt {o['avg_attacks']} Angriffe je Kampf.</p>")
    parts.append("<h2>Runs je Bot</h2>")
    parts.append(table([dict(bot=k, **v) for k, v in summary["groups"].items()],
                       [("bot", "Bot"), ("runs", "Runs"), ("avg_wins", "Siege"), ("victory_rate", "10 Siege %"), ("avg_days", "Tage")]))
    fig, ax = plt.subplots(figsize=(7, 3))
    for bot, g in summary["groups"].items():
        if bot == "alle":
            continue
        xs = list(range(0, 11))
        total = max(g["runs"], 1)
        ax.plot(xs, [100.0 * g["wins_hist"].get(x, 0) / total for x in xs], marker="o", label=bot)
    ax.set_xlabel("Siege am Run-Ende")
    ax.set_ylabel("% der Runs")
    ax.legend()
    parts.append(chart(fig))

    parts.append("<h2>Einheiten nach bereinigter Winrate</h2>")
    parts.append("<p>„Schaden %“ = Anteil am Schaden des eigenen Teams, „Carry %“ = in gewonnenen Kämpfen "
                 "der höchste Schaden im Team. Beschworene Spielsteine zählen für ihre Beschwörerin.</p>")
    parts.append(f"<p>„± Sel.“ = Abstand zum Schnitt der eigenen Seltenheit. Rot = mehr als {RARITY_GAP:.0f} Punkte darüber, "
                 f"blau = mehr als {RARITY_GAP:.0f} darunter, jeweils ab {MIN_SAMPLES} Kämpfen.</p>")
    parts.append(table(units, [("id", "Id"), ("name", "Name"), ("rarity", "Sel."), ("cost", "Preis"), ("colors", "Farben"),
                               ("winrate", "Winrate"), ("vs_rarity", "± Sel."), ("winrate_früh", "früh"), ("winrate_mitte", "mitte"), ("winrate_spät", "spät"),
                               ("battles", "Kämpfe"), ("pick_rate", "Pick %"), ("level3_share", "Stufe 3 %"),
                               ("avg_damage", "Ø Schaden"), ("damage_share", "Schaden %"), ("carry_rate", "Carry %"),
                               ("ghost_strength", "Ø Teamstärke"), ("bg_name", "BG-Vorlage"), ("bg_avg_placement", "BG-Platz")]))

    fig, ax = plt.subplots(figsize=(7, 4))
    for r in range(5):
        pts = [u for u in units if u["rarity"] == r]
        ax.scatter([u["cost"] for u in pts], [u["winrate"] for u in pts], label=RARITY_NAMES[r], s=28)
    ax.axhline(50, color="#999", lw=0.8)
    ax.set_xlabel("Preis")
    ax.set_ylabel("bereinigte Winrate %")
    ax.legend(fontsize=8)
    parts.append("<h2>Preis gegen Stärke</h2><p>Gleiche Preise sollten ähnlich stark sein.</p>" + chart(fig))

    parts.append("<h2>Seltenheiten</h2>")
    parts.append(table(summary["rarity"], [("name", "Seltenheit"), ("units", "Einheiten"), ("winrate_mean", "Winrate Schnitt"), ("winrate_spread", "Streuung")]))
    parts.append("<h2>Farben (Teams mit mindestens 3 Einheiten der Farbe)</h2>")
    parts.append(table(summary["colors"], [("color", "Farbe"), ("battles", "Kämpfe"), ("share", "Anteil %"), ("winrate", "Winrate")]))

    c = summary["bg_compare"]
    parts.append("<h2>Abgleich mit echten BG-Daten</h2>")
    parts.append(f"<p>Rangkorrelation zwischen unserer Winrate und dem BG-Durchschnittsplatz der Vorlage: "
                 f"<b>{c['spearman']}</b> bei {c['n']} Einheiten. 1 = gleiche Reihenfolge, 0 = kein Zusammenhang. "
                 "Ein niedriger Wert ist zu erwarten, weil Preis, Shop und Farben anders sind; auffällige Ausreißer lohnen einen Blick.</p>")
    pts = [u for u in units if u["bg_avg_placement"] is not None]
    if pts:
        fig, ax = plt.subplots(figsize=(7, 4))
        ax.scatter([u["bg_avg_placement"] for u in pts], [u["winrate"] for u in pts], s=24)
        for u in pts:
            ax.annotate(u["id"], (u["bg_avg_placement"], u["winrate"]), fontsize=6)
        ax.invert_xaxis()
        ax.set_xlabel("BG-Durchschnittsplatz (rechts = stärker)")
        ax.set_ylabel("Workshop-Winrate %")
        parts.append(chart(fig))

    parts.append("<h2>Tage</h2>")
    parts.append(table(summary["days"], [("day", "Tag"), ("battles", "Kämpfe"), ("winrate", "Winrate %"), ("avg_attacks", "Angriffe"), ("gold_left", "Gold übrig")]))

    style = ("body{font-family:system-ui,sans-serif;max-width:1100px;margin:24px auto;padding:0 16px;color:#222}"
             "table{border-collapse:collapse;font-size:13px;margin:8px 0}td,th{border:1px solid #ddd;padding:3px 6px;text-align:right}"
             "th{background:#f3f3f3}.flag-stark td{background:#fde2e1}.flag-schwach td{background:#e1ecfd}.meta{color:#777}img{max-width:100%}")
    return f"<!doctype html><html lang=de><meta charset=utf-8><title>Workshop-Bericht</title><style>{style}</style><body>{''.join(parts)}</body></html>"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--ruleset", required=True)
    ap.add_argument("--out-dir")
    a = ap.parse_args()
    log = Path(a.log)
    ruleset_dir = Path(a.ruleset)
    out_dir = Path(a.out_dir) if a.out_dir else log.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    units_data = json.loads((ruleset_dir / "units.json").read_text())
    units = {u["id"]: u for u in units_data["units"]}
    df = load_log(log)
    summary = analyze(df, units, ruleset_dir)
    combat = str(df["combat"].dropna().iloc[0]) if "combat" in df else ""
    summary["combat"] = combat
    summary["ruleset"] = ruleset_dir.name
    (out_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1, default=float))
    (out_dir / "report.html").write_text(report(summary, str(log), ruleset_dir.name, combat))
    flagged = [u for u in summary["units"] if u["flag"]]
    print(f"Bericht: {out_dir / 'report.html'} ({len(flagged)} Einheiten mit Warnung, "
          f"BG-Abgleich {summary['bg_compare']['spearman']})")


if __name__ == "__main__":
    main()
