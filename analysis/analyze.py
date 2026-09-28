"""Wertet das JSON-Lines-Log aus tools/simulate.gd (oder echte Runs) aus und schreibt report.html.

Aufruf (aus dem Repo-Root):
    analysis/.venv/bin/python analysis/analyze.py logs/sim.jsonl [--out analysis/report.html]

Einrichtung der Umgebung (einmalig):
    python3 -m venv analysis/.venv && analysis/.venv/bin/pip install -r analysis/requirements.txt

Kennzahlen und Warnschwellen wie in PLAN.md, Abschnitt 6. Winrates immer je Runde getrennt,
sonst verfälscht der Selektionseffekt das Bild (starke Teams erreichen spätere Runden).
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

# Warnschwellen aus PLAN.md
WINRATE_HIGH = 60.0
WINRATE_LOW = 40.0
PICK_HIGH = 50.0
PICK_LOW = 10.0
TRAINER_GAP = 1.0
DURATION_MAX_S = 40.0
DRAW_MAX = 10.0
# Unterhalb dieser Stichprobe keine Warnung, das Rauschen ist zu groß.
MIN_SAMPLES = 50

RESULT_SCORE = {"win": 1.0, "draw": 0.5, "loss": 0.0}


def load(path: Path) -> pd.DataFrame:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    if not rows:
        raise SystemExit(f"Keine Ereignisse in {path}")
    return pd.DataFrame(rows)


def chart(fig) -> str:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight")
    plt.close(fig)
    return '<img alt="Diagramm" src="data:image/png;base64,%s">' % base64.b64encode(buf.getvalue()).decode()


def group_label(df: pd.DataFrame) -> pd.Series:
    """Bot-Name bei Simulationen, sonst 'spieler' für echte Runs."""
    if "bot" in df.columns:
        return df["bot"].fillna("spieler")
    return pd.Series("spieler", index=df.index)


# --- Kennzahlen ---


def monster_winrates(battles: pd.DataFrame):
    """Kampf-Winrate je Monster und Runde. Jedes Monster zählt pro Kampf einmal.

    Bereinigt heißt: Abstand zum Schnitt aller Kämpfe derselben Runde, plus 50. Die Schwellen aus
    PLAN.md setzen einen Schnitt von 50 % voraus. Gegen Geister ohne Trainer und Trinkets liegt er
    höher, bereinigt bleibt der Vergleich zwischen Monstern trotzdem fair.
    """
    baseline = battles.groupby("round")["result"].apply(lambda s: s.map(RESULT_SCORE).mean())
    rows = []
    for _, b in battles.iterrows():
        ids = {tag.split(":")[0] for tag in b["team"]}
        score = RESULT_SCORE[b["result"]]
        for monster in ids:
            rows.append({"monster": monster, "round": b["round"], "score": score,
                         "adjusted": score - baseline[b["round"]] + 0.5})
    df = pd.DataFrame(rows)
    rate = df.pivot_table(index="monster", columns="round", values="adjusted", aggfunc="mean") * 100
    count = df.pivot_table(index="monster", columns="round", values="score", aggfunc="count").fillna(0).astype(int)
    overall = df.groupby("monster").agg(roh=("score", "mean"), bereinigt=("adjusted", "mean"), kaempfe=("score", "count"))
    overall[["roh", "bereinigt"]] *= 100
    return rate, count, overall, baseline * 100


def pick_rates(shops: pd.DataFrame) -> pd.DataFrame:
    offered = shops.explode("offered")["offered"].value_counts()
    bought = shops.explode("bought")["bought"].dropna().value_counts()
    df = pd.DataFrame({"angeboten": offered, "gekauft": bought}).fillna(0).astype(int)
    df["pick_rate"] = df["gekauft"] / df["angeboten"].where(df["angeboten"] > 0) * 100
    return df.sort_values("pick_rate", ascending=False)


def trinket_rates(trinkets: pd.DataFrame) -> pd.DataFrame:
    if trinkets.empty:
        return pd.DataFrame()
    offered = trinkets.explode("offered")["offered"].value_counts()
    chosen = trinkets["chosen"].value_counts()
    df = pd.DataFrame({"angeboten": offered, "gewählt": chosen}).fillna(0).astype(int)
    df["wahl_rate"] = df["gewählt"] / df["angeboten"] * 100
    return df.sort_values("wahl_rate", ascending=False)


def wins_by(ends: pd.DataFrame, column: str) -> pd.DataFrame:
    g = ends.groupby(column)
    df = pd.DataFrame({
        "runs": g.size(),
        "siege_schnitt": g["wins"].mean(),
        "runs_gewonnen_pct": g["victory"].mean() * 100,
    })
    df["abstand_zum_schnitt"] = df["siege_schnitt"] - ends["wins"].mean()
    return df


# --- HTML ---


def fmt_table(df: pd.DataFrame, highlight=None, digits=1) -> str:
    """highlight(spalte, wert) -> True markiert die Zelle als Warnung."""
    head = "".join(f"<th>{html.escape(str(c))}</th>" for c in [df.index.name or ""] + list(df.columns))
    body = []
    for idx, row in df.iterrows():
        cells = [f"<th>{html.escape(str(idx))}</th>"]
        for col, val in row.items():
            if isinstance(val, float):
                text = "" if pd.isna(val) else f"{val:.{digits}f}"
            else:
                text = html.escape(str(val))
            cls = ' class="warn"' if highlight and not pd.isna(val) and highlight(col, val, idx) else ""
            cells.append(f"<td{cls}>{text}</td>")
        body.append("<tr>" + "".join(cells) + "</tr>")
    return f'<div class="table"><table><thead><tr>{head}</tr></thead><tbody>{"".join(body)}</tbody></table></div>'


def build_report(df: pd.DataFrame, source: Path) -> str:
    df = df.copy()
    df["gruppe"] = group_label(df)
    battles = df[df["ev"] == "battle"].copy()
    shops = df[df["ev"] == "shop"].copy()
    ends = df[df["ev"] == "run_end"].copy()
    trinkets = df[df["ev"] == "trinket"].copy()
    # run_end hat keine Runde, deshalb liest pandas die Spalte als Float.
    battles["round"] = battles["round"].astype(int)
    if not ends.empty:
        ends["victory"] = ends["victory"].astype(bool)
    warnings = []

    versions = ", ".join(sorted(df["v"].dropna().astype(str).unique()))
    sections = []

    # 1. Winrate je Monster und Runde
    rate, count, overall, baseline = monster_winrates(battles)
    for monster, row in overall.iterrows():
        if row["kaempfe"] >= MIN_SAMPLES and not WINRATE_LOW <= row["bereinigt"] <= WINRATE_HIGH:
            warnings.append(f"Monster {monster}: bereinigte Kampf-Winrate {row['bereinigt']:.1f} % über alle Runden")
    for monster in rate.index:
        flagged = []
        for rnd in rate.columns:
            n = count.loc[monster, rnd]
            v = rate.loc[monster, rnd]
            if n >= MIN_SAMPLES and not pd.isna(v) and not WINRATE_LOW <= v <= WINRATE_HIGH:
                flagged.append(f"R{rnd}: {v:.0f} %")
        if flagged:
            warnings.append(f"Monster {monster} auffällig in {len(flagged)} Runden ({', '.join(flagged)})")
    rate.index.name = "Monster"
    fig, ax = plt.subplots(figsize=(9, 4.5))
    im = ax.imshow(rate.values, cmap="RdYlGn", vmin=20, vmax=80, aspect="auto")
    ax.set_xticks(range(len(rate.columns)), [str(c) for c in rate.columns])
    ax.set_yticks(range(len(rate.index)), rate.index)
    ax.set_xlabel("Runde")
    ax.set_title("Bereinigte Kampf-Winrate je Monster und Runde (%)")
    fig.colorbar(im, ax=ax)
    table = rate.round(1)
    table.columns = [f"R{c}" for c in table.columns]
    overall.index.name = "Monster"
    base_text = ", ".join(f"R{r}: {v:.0f} %" for r, v in baseline.items())
    sections.append(("Kampf-Winrate je Monster und Runde",
                     f"Bereinigt = Abstand zum Rundenschnitt plus 50. Rundenschnitt aller Kämpfe: {base_text}. "
                     f"Warnsignal unter {WINRATE_LOW:.0f} % oder über {WINRATE_HIGH:.0f} % ab {MIN_SAMPLES} Kämpfen. "
                     "Unentschieden zählt halb.",
                     fmt_table(overall.sort_values("bereinigt", ascending=False),
                               lambda c, v, i: c == "bereinigt" and not WINRATE_LOW <= v <= WINRATE_HIGH)
                     + chart(fig) + fmt_table(table, lambda c, v, i: (count.loc[i, int(c[1:])] >= MIN_SAMPLES)
                                              and not WINRATE_LOW <= v <= WINRATE_HIGH)))

    # 2. Pick-Rate
    picks = pick_rates(shops)
    picks.index.name = "Monster"
    for monster, row in picks.iterrows():
        if row["angeboten"] >= MIN_SAMPLES and not PICK_LOW <= row["pick_rate"] <= PICK_HIGH:
            warnings.append(f"Monster {monster}: Pick-Rate {row['pick_rate']:.1f} %")
    trinket_table = trinket_rates(trinkets)
    trinket_html = ""
    if not trinket_table.empty:
        trinket_table.index.name = "Trinket"
        trinket_html = "<h3>Trinket-Wahl</h3>" + fmt_table(trinket_table)
    sections.append(("Pick-Rate (gekauft / angeboten)",
                     f"Warnsignal unter {PICK_LOW:.0f} % oder über {PICK_HIGH:.0f} %.",
                     fmt_table(picks, lambda c, v, i: c == "pick_rate" and not PICK_LOW <= v <= PICK_HIGH) + trinket_html))

    if ends.empty:
        sections.append(("Siege pro Run", "Noch keine abgeschlossenen Runs im Log.", ""))
    else:
        # 3. Siege pro Run je Trainer und Bot
        by_trainer = wins_by(ends, "trainer")
        by_trainer.index.name = "Trainer"
        by_group = wins_by(ends, "gruppe")
        by_group.index.name = "Bot"
        for trainer, row in by_trainer.iterrows():
            if abs(row["abstand_zum_schnitt"]) > TRAINER_GAP:
                warnings.append(f"Trainer {trainer}: {row['abstand_zum_schnitt']:+.2f} Siege zum Schnitt")
        cross = ends.pivot_table(index="gruppe", columns="trainer", values="wins", aggfunc="mean")
        cross.index.name = "Bot / Trainer"
        sections.append(("Siege pro Run je Trainer und Bot",
                         f"Warnsignal, wenn ein Trainer mehr als {TRAINER_GAP:.0f} Sieg vom Schnitt abweicht.",
                         fmt_table(by_trainer, lambda c, v, i: c == "abstand_zum_schnitt" and abs(v) > TRAINER_GAP, 2)
                         + fmt_table(by_group, digits=2) + "<h3>Siege je Bot und Trainer</h3>" + fmt_table(cross, digits=2)))

        # 4. Verteilung der Siege
        max_wins = int(ends["wins"].max())
        fig, ax = plt.subplots(figsize=(9, 4))
        groups = sorted(ends["gruppe"].unique())
        width = 0.8 / max(len(groups), 1)
        for k, g in enumerate(groups):
            counts = ends[ends["gruppe"] == g]["wins"].value_counts(normalize=True).reindex(range(max_wins + 1), fill_value=0)
            ax.bar([x + k * width for x in counts.index], counts.values * 100, width=width, label=g)
        ax.set_xlabel("Siege am Run-Ende")
        ax.set_ylabel("Anteil der Runs (%)")
        ax.set_title("Verteilung der Siege pro Run")
        ax.legend()
        # Wand: Runs, die bei einer Siegzahl deutlich häufiger enden als bei den Nachbarn.
        dist = ends[~ends["victory"]]["wins"].value_counts(normalize=True).sort_index() * 100
        for w, share in dist.items():
            neighbours = [dist.get(w - 1, 0), dist.get(w + 1, 0)]
            if share > 15 and share > 2 * max(neighbours):
                warnings.append(f"Mögliche Wand: {share:.1f} % der verlorenen Runs enden bei {w} Siegen")
        sections.append(("Verteilung der Siege pro Run",
                         "Eine einzelne Spitze bei einer Siegzahl deutet auf eine Wand hin.", chart(fig)))

    # 5. Kampfdauer und 6. Unentschieden
    dur = battles["duration_s"]
    long_share = (dur > DURATION_MAX_S).mean() * 100
    draw_share = (battles["result"] == "draw").mean() * 100
    if long_share > 5:
        warnings.append(f"{long_share:.1f} % der Kämpfe dauern länger als {DURATION_MAX_S:.0f} s")
    if draw_share > DRAW_MAX:
        warnings.append(f"Unentschieden: {draw_share:.1f} % der Kämpfe")
    fig, ax = plt.subplots(figsize=(9, 3.5))
    ax.hist(dur, bins=40, color="#6b5fb5")
    ax.axvline(DURATION_MAX_S, color="#c0392b", linestyle="--", label=f"{DURATION_MAX_S:.0f} s")
    ax.set_xlabel("Geschätzte Dauer bei 1x (s)")
    ax.set_ylabel("Kämpfe")
    ax.legend()
    by_round = battles.groupby("round").agg(kaempfe=("duration_s", "size"), dauer_schnitt=("duration_s", "mean"),
                                            dauer_p90=("duration_s", lambda s: s.quantile(0.9)),
                                            ticks_schnitt=("ticks", "mean"))
    by_round["unentschieden_pct"] = battles.groupby("round")["result"].apply(lambda s: (s == "draw").mean() * 100)
    by_round["winrate_pct"] = battles.groupby("round")["result"].apply(lambda s: s.map(RESULT_SCORE).mean() * 100)
    by_round.index.name = "Runde"
    sections.append(("Kampfdauer und Unentschieden",
                     f"Schnitt {dur.mean():.1f} s, 90 % unter {dur.quantile(0.9):.1f} s, "
                     f"{long_share:.1f} % über {DURATION_MAX_S:.0f} s. Unentschieden: {draw_share:.1f} % "
                     f"(Warnsignal über {DRAW_MAX:.0f} %).",
                     chart(fig) + fmt_table(by_round, lambda c, v, i: (c == "dauer_p90" and v > DURATION_MAX_S)
                                            or (c == "unentschieden_pct" and v > DRAW_MAX))))

    warn_html = "".join(f"<li>{html.escape(w)}</li>" for w in warnings) or "<li class='ok'>Keine Warnsignale.</li>"
    body = "".join(f"<section><h2>{html.escape(t)}</h2><p>{html.escape(d)}</p>{c}</section>" for t, d, c in sections)
    return TEMPLATE.format(
        source=html.escape(str(source)), created=datetime.now().strftime("%d.%m.%Y %H:%M"),
        versions=html.escape(versions), runs=len(ends), battles=len(battles),
        avg_wins=ends["wins"].mean() if not ends.empty else 0.0,
        victories=ends["victory"].mean() * 100 if not ends.empty else 0.0,
        warn_count=len(warnings), warnings=warn_html, body=body)


TEMPLATE = """<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Inklite Balancing-Bericht</title>
<style>
:root {{ --bg:#faf9fc; --fg:#1b1726; --muted:#6c6680; --warn:#fbe3e0; --warn-fg:#a3261a; --line:#e3e0ea; }}
body {{ margin:0; padding:24px 16px; background:var(--bg); color:var(--fg); font:15px/1.5 system-ui, sans-serif; }}
main {{ max-width:1000px; margin:0 auto; }}
h1 {{ margin:0 0 4px; }} h2 {{ margin-top:36px; border-bottom:1px solid var(--line); padding-bottom:4px; }}
.meta {{ color:var(--muted); }}
.stats {{ display:flex; flex-wrap:wrap; gap:12px; margin:16px 0; }}
.stat {{ background:#fff; border:1px solid var(--line); border-radius:8px; padding:10px 14px; min-width:120px; }}
.stat b {{ display:block; font-size:22px; }}
.warnings li {{ color:var(--warn-fg); }} .warnings li.ok {{ color:#1e7a3c; }}
.table {{ overflow-x:auto; margin:12px 0; }}
table {{ border-collapse:collapse; font-size:13px; background:#fff; }}
th, td {{ border:1px solid var(--line); padding:4px 8px; text-align:right; white-space:nowrap; }}
thead th {{ background:#f0eef5; }} tbody th {{ text-align:left; }}
td.warn {{ background:var(--warn); color:var(--warn-fg); font-weight:600; }}
img {{ max-width:100%; height:auto; }}
</style></head><body><main>
<h1>Inklite Balancing-Bericht</h1>
<p class="meta">Quelle: {source} · erstellt {created} · Spielversion {versions}</p>
<div class="stats">
<div class="stat"><b>{runs}</b>Runs</div><div class="stat"><b>{battles}</b>Kämpfe</div>
<div class="stat"><b>{avg_wins:.2f}</b>Siege pro Run</div><div class="stat"><b>{victories:.1f} %</b>Runs gewonnen</div>
<div class="stat"><b>{warn_count}</b>Warnsignale</div>
</div>
<h2>Warnsignale</h2><ul class="warnings">{warnings}</ul>
{body}
</main></body></html>
"""


def main():
    parser = argparse.ArgumentParser(description="Inklite Balancing-Bericht aus JSON Lines")
    parser.add_argument("log", type=Path)
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "report.html")
    args = parser.parse_args()
    df = load(args.log)
    args.out.write_text(build_report(df, args.log), encoding="utf-8")
    ends = df[df["ev"] == "run_end"]
    print(f"Bericht: {args.out} ({len(ends)} Runs, {int((df['ev'] == 'battle').sum())} Kämpfe)")


if __name__ == "__main__":
    main()
