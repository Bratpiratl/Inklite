"""Prüft einen Workshop-Regelsatz, bevor der Editor ihn speichert.

SCHEMA beschreibt die erlaubten Bausteine. Es ist die Quelle für die Auswahllisten im Editor
und muss zu game/core/ws_combat.gd und ws_run.gd passen.
"""

SCHEMA = {
    "triggers": {
        "start_of_combat": "Kampfbeginn",
        "on_attack": "Beim Angriff (vor dem Treffer)",
        "after_attack": "Nach dem Angriff",
        "on_hurt": "Wenn diese Einheit Schaden nimmt",
        "on_death": "Todesröcheln",
        "on_ally_death": "Wenn ein Verbündeter stirbt",
        "avenge": "Rache",
        "on_summon": "Wenn ein Verbündeter beschworen wird",
        "on_ally_attack": "Wenn ein Verbündeter angreift",
        "on_kill": "Wenn diese Einheit einen Gegner tötet",
        "on_shield_lost": "Wenn diese Einheit ihren Gottesschild verliert",
        "on_ally_shield_lost": "Wenn ein Verbündeter seinen Gottesschild verliert",
        "on_reborn": "Wenn ein Verbündeter wiederaufersteht",
        "after_deathrattle": "Nach einem Todesröcheln eines Verbündeten",
        "on_buy": "Beim Kauf (Kampfschrei)",
        "on_sell": "Beim Verkauf",
        "end_of_turn": "Am Ende der Shop-Phase",
        "start_of_turn": "Zu Beginn eines Tages",
        "on_ally_buy": "Wenn du eine andere Einheit kaufst",
        "after_battlecry": "Nach einem Kampfschrei",
        "on_reroll": "Beim Neu würfeln",
    },
    "shop_triggers": ["on_buy", "on_sell", "end_of_turn", "start_of_turn", "on_ally_buy", "after_battlecry", "on_reroll"],
    "effects": {
        "buff": "Werte erhöhen (atk, hp, optional keyword, permanent)",
        "give_keyword": "Schlüsselwort geben (oder random)",
        "remove_keyword": "Schlüsselwörter entfernen",
        "summon": "Beschwören (token oder random: deathrattle)",
        "damage": "Schaden (value oder value_from)",
        "destroy": "Vernichten",
        "attack_now": "Sofort angreifen",
        "trigger_ability": "Fähigkeit eines Ziels auslösen (ability_trigger)",
        "gold": "Gold erhalten (nur Shop)",
        "free_reroll": "Gratis-Würfe (nur Shop)",
    },
    "targets": {
        "self": "sich selbst", "adjacent": "Nachbarn", "ally_random": "zufälliger Verbündeter",
        "ally_random_other": "zufälliger anderer Verbündeter", "allies_all": "alle Verbündeten",
        "allies_other": "alle anderen Verbündeten", "ally_leftmost": "Verbündeter ganz links",
        "trigger_unit": "auslösende Einheit", "target": "Angriffsziel", "attacker": "Angreifer",
        "killer": "wer diese Einheit getötet hat", "enemy_random": "zufälliger Gegner",
        "enemies_all": "alle Gegner", "enemy_highest_hp": "Gegner mit den meisten HP",
        "all_others": "alle anderen Einheiten beider Seiten",
    },
    "keywords": {
        "taunt": "Spott", "divine_shield": "Gottesschild", "reborn": "Wiedergeburt", "windfury": "Windzorn",
        "venomous": "Giftig", "cleave": "Spalten", "stealth": "Verstohlenheit",
    },
    "passives": {
        "deathrattle_twice": "Todesröcheln doppelt", "battlecry_twice": "Kampfschreie doppelt",
        "end_of_turn_twice": "Rundenende-Effekte doppelt",
    },
    "value_from": {"atk": "eigener Angriff", "trigger_atk": "Angriff der auslösenden Einheit",
                   "target_atk": "Angriff des Ziels", "excess": "überschüssiger Schaden"},
    "fields": ["trigger", "effect", "target", "atk", "hp", "value", "value_from", "keyword", "keywords", "token",
               "random", "times", "picks", "count", "only", "when", "permanent", "include_self", "ability_trigger"],
}


def _ability_problems(where, ability, token_ids, color_ids):
    p = []
    if not isinstance(ability, dict):
        return [f"{where}: Fähigkeit ist kein Objekt"]
    for key in ability:
        if key not in SCHEMA["fields"]:
            p.append(f"{where}: unbekanntes Feld {key}")
    trig, eff = ability.get("trigger"), ability.get("effect")
    if trig not in SCHEMA["triggers"]:
        p.append(f"{where}: unbekannter Auslöser {trig}")
    if eff not in SCHEMA["effects"]:
        p.append(f"{where}: unbekannter Effekt {eff}")
    if "target" in ability and ability["target"] not in SCHEMA["targets"]:
        p.append(f"{where}: unbekanntes Ziel {ability['target']}")
    if eff == "summon" and not ability.get("token") and ability.get("random") != "deathrattle":
        p.append(f"{where}: summon braucht token oder random")
    if ability.get("token") and ability["token"] not in token_ids:
        p.append(f"{where}: Spielstein {ability['token']} fehlt")
    if trig == "avenge" and int(ability.get("count", 0) or 0) < 1:
        p.append(f"{where}: avenge braucht count ab 1")
    for kw in [ability.get("keyword")] + list(ability.get("keywords", []) or []):
        if kw and kw != "random" and kw not in SCHEMA["keywords"]:
            p.append(f"{where}: unbekanntes Schlüsselwort {kw}")
    if ability.get("value_from") and ability["value_from"] not in SCHEMA["value_from"]:
        p.append(f"{where}: unbekanntes value_from {ability['value_from']}")
    for f in ("only", "when"):
        flt = ability.get(f)
        if flt is not None:
            if not isinstance(flt, dict):
                p.append(f"{where}: {f} muss ein Objekt sein")
            elif flt.get("color") and flt["color"] not in color_ids:
                p.append(f"{where}: unbekannte Farbe {flt['color']}")
    for f in ("atk", "hp", "value", "times", "picks", "count"):
        if f in ability and not isinstance(ability[f], int):
            p.append(f"{where}: {f} muss eine ganze Zahl sein")
    return p


def check(ruleset, units):
    p = []
    if not isinstance(ruleset, dict) or not isinstance(units, dict):
        return ["Regelsatz oder Einheiten fehlen"]
    color_ids = {c["id"] for c in ruleset.get("colors", [])}
    n_rarities = len(ruleset.get("rarities", []))
    token_ids = {t.get("id") for t in units.get("tokens", [])}
    ids = set()
    for u in units.get("units", []) + units.get("tokens", []):
        uid = u.get("id", "?")
        if uid in ids:
            p.append(f"{uid}: Id doppelt")
        ids.add(uid)
        for f in ("atk", "hp"):
            if not isinstance(u.get(f), int) or u[f] < 0:
                p.append(f"{uid}: {f} muss eine ganze Zahl ab 0 sein")
        if u.get("hp", 1) == 0:
            p.append(f"{uid}: hp darf nicht 0 sein")
        for c in u.get("colors", []):
            if c not in color_ids:
                p.append(f"{uid}: unbekannte Farbe {c}")
        for kw in u.get("keywords", []):
            if kw not in SCHEMA["keywords"]:
                p.append(f"{uid}: unbekanntes Schlüsselwort {kw}")
        for ps in u.get("passives", []):
            if ps not in SCHEMA["passives"]:
                p.append(f"{uid}: unbekannte Passive {ps}")
        for i, a in enumerate(u.get("abilities", [])):
            p += _ability_problems(f"{uid} Fähigkeit {i + 1}", a, token_ids, color_ids)
    for u in units.get("units", []):
        uid = u.get("id", "?")
        if not isinstance(u.get("rarity"), int) or not 0 <= u["rarity"] < max(n_rarities, 1):
            p.append(f"{uid}: Seltenheit ungültig")
        if not isinstance(u.get("cost"), int) or u["cost"] < 0:
            p.append(f"{uid}: Preis muss eine ganze Zahl ab 0 sein")
    table = ruleset.get("shop", {}).get("rarity_weights_by_rank", [])
    if not table:
        p.append("Shop: Chancentabelle fehlt")
    for i, row in enumerate(table):
        if len(row) != n_rarities or any(not isinstance(v, int) or v < 0 for v in row) or sum(row) <= 0:
            p.append(f"Shop: Rang {i + 1} braucht {n_rarities} ganze Zahlen ab 0 mit Summe über 0")
    eco = ruleset.get("economy", {})
    if not eco.get("income_by_day") or any(not isinstance(v, int) for v in eco.get("income_by_day", [])):
        p.append("Wirtschaft: Einkommen je Tag muss eine Liste ganzer Zahlen sein")
    if ruleset.get("combat", {}).get("mode") not in ("bg", "grid"):
        p.append("Kampf: Modus muss bg oder grid sein")
    board = ruleset.get("board", {})
    if ruleset.get("combat", {}).get("mode") == "grid":
        g = ruleset.get("combat", {}).get("grid", {})
        if int(g.get("cols", 3)) * int(g.get("rows", 2)) < int(board.get("team_slots", 6)):
            p.append("Kampf: Raster hat weniger Felder als Teamplätze")
    return p
