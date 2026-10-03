"use strict";
// Inklite Workshop: Editor für Regelsatz, Einheiten, Shop, Simulation und Protokoll.

const S = {
  name: "", data: null, saved: "", schema: null, runs: [], summary: null, summaries: {},
  filters: { q: "", rarity: "", color: "", status: "", flag: "" }, sort: { key: "id", dir: 1 },
  compare: { a: "", b: "" }, job: null, poll: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const clone = (o) => JSON.parse(JSON.stringify(o));

async function api(path, body) {
  const opts = body === undefined ? {} : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
  const res = await fetch("api/" + path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || res.statusText), { data });
  return data;
}

function toast(msg, ms = 2600) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), ms);
}

// --- Laden und Speichern ---

async function init() {
  document.querySelectorAll("#tabs button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
  $("#btn-save").addEventListener("click", openSaveDialog);
  $("#btn-copy").addEventListener("click", copyRuleset);
  $("#ruleset-select").addEventListener("change", (e) => {
    if (isDirty() && !confirm("Ungespeicherte Änderungen verwerfen?")) { e.target.value = S.name; return; }
    loadRuleset(e.target.value);
  });
  window.addEventListener("beforeunload", (e) => { if (isDirty()) { e.preventDefault(); e.returnValue = ""; } });
  const { rulesets } = await api("rulesets");
  $("#ruleset-select").innerHTML = rulesets.map((n) => `<option>${esc(n)}</option>`).join("");
  if (rulesets.length) await loadRuleset(localStorage.getItem("ws-ruleset") && rulesets.includes(localStorage.getItem("ws-ruleset")) ? localStorage.getItem("ws-ruleset") : rulesets[0]);
  const tab = localStorage.getItem("ws-tab");
  if (tab) showTab(tab);
  pollJob();
}

async function loadRuleset(name) {
  const d = await api("ruleset/" + name);
  S.name = name;
  S.schema = d.schema;
  S.data = { ruleset: d.ruleset, units: d.units };
  S.playBuilt = d.play_built;
  S.saved = JSON.stringify(S.data);
  try { localStorage.setItem("ws-ruleset", name); } catch (e) { /* egal */ }
  $("#ruleset-select").value = name;
  await loadRuns();
  renderAll();
}

async function loadRuns() {
  S.runs = (await api("runs/" + S.name)).runs;
  const latest = S.runs.find((r) => r.has_report);
  S.summary = latest ? await summaryOf(latest.run) : null;
}

async function summaryOf(run) {
  if (!S.summaries[run]) S.summaries[run] = await api(`run/${S.name}/${run}`);
  return S.summaries[run];
}

function isDirty() { return S.data && JSON.stringify(S.data) !== S.saved; }

function markDirty() {
  const d = isDirty();
  $("#dirty").hidden = !d;
  $("#btn-save").disabled = !d;
}

function renderAll() {
  renderUnits(); renderShop(); renderRules(); renderSim(); renderLog(); renderHelp(); markDirty();
}

function showTab(tab) {
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
  document.querySelectorAll(".tab").forEach((s) => s.classList.toggle("active", s.id === "tab-" + tab));
  try { localStorage.setItem("ws-tab", tab); } catch (e) { /* egal */ }
  if (tab === "log") renderLog();
}

function openModal(html) {
  const m = $("#modal");
  m.querySelector(".modal-box").innerHTML = html;
  m.hidden = false;
  return m.querySelector(".modal-box");
}
function closeModal() { $("#modal").hidden = true; }

function openSaveDialog() {
  const box = openModal(`
    <h2>Änderung speichern</h2>
    <p class="muted">Schreib kurz auf, was du geändert hast und was du erwartest. Nach der Simulation trägst du im Protokoll ein, ob es eingetroffen ist.</p>
    <label class="field"><span>Was und warum</span><textarea id="save-note" placeholder="z. B. Dornengolem Preis 45 auf 50, weil spät über 60 %"></textarea></label>
    <label class="field"><span>Vorhersage</span><textarea id="save-pred" placeholder="z. B. Winrate spät sinkt auf etwa 56 %, Pick-Rate sinkt leicht"></textarea></label>
    <div class="row"><button class="primary" id="save-go">Speichern</button><button id="save-cancel">Abbrechen</button></div>
    <div id="save-problems"></div>`);
  box.querySelector("#save-cancel").onclick = closeModal;
  box.querySelector("#save-go").onclick = async () => {
    try {
      const res = await api("ruleset/" + S.name, { ...S.data, note: $("#save-note").value, prediction: $("#save-pred").value });
      closeModal();
      await loadRuleset(S.name);
      toast(res.changes.length ? `Gespeichert als Version ${res.version} (${res.changes.length} Änderungen)` : "Keine Änderungen");
    } catch (e) {
      const probs = (e.data && e.data.problems) || [e.message];
      box.querySelector("#save-problems").innerHTML = `<div class="card" style="background:var(--warn-hi)"><b>Nicht gespeichert:</b><ul>${probs.map((p) => `<li>${esc(p)}</li>`).join("")}</ul></div>`;
    }
  };
}

async function copyRuleset() {
  const name = prompt("Name der Kopie (Kleinbuchstaben, Ziffern, _ oder -):", S.name + "_v2");
  if (!name) return;
  try {
    await api(`ruleset/${S.name}/copy`, { name });
    const { rulesets } = await api("rulesets");
    $("#ruleset-select").innerHTML = rulesets.map((n) => `<option>${esc(n)}</option>`).join("");
    await loadRuleset(name);
    toast("Kopie angelegt: " + name);
  } catch (e) { toast(e.message); }
}

// --- Texte ---

const RULES = () => S.data.ruleset;
const UNITS = () => S.data.units.units;
const TOKENS = () => S.data.units.tokens || [];
const colorOf = (id) => (RULES().colors || []).find((c) => c.id === id) || { id, name: id, hex: "#999" };
const rarityName = (r) => (RULES().rarities || [])[r] ?? r;
const dot = (c) => `<span class="color-dot" style="background:${esc(colorOf(c).hex)}" title="${esc(colorOf(c).name)}"></span>`;
const kwName = (k) => (S.schema.keywords[k] || k);
const unitName = (id) => { const u = UNITS().concat(TOKENS()).find((x) => x.id === id); return u ? u.name : id; };

function abilitySentence(a) {
  const sch = S.schema;
  const trig = sch.triggers[a.trigger] || a.trigger;
  const tgt = sch.targets[a.target || "self"] || a.target;
  const only = a.only ? " (" + [a.only.color && colorOf(a.only.color).name, a.only.keyword && kwName(a.only.keyword), a.only.has_trigger && "mit " + (sch.triggers[a.only.has_trigger] || a.only.has_trigger)].filter(Boolean).join(", ") + ")" : "";
  const when = a.when ? " [nur wenn " + [a.when.color && colorOf(a.when.color).name, a.when.has_trigger && "mit " + (sch.triggers[a.when.has_trigger] || a.when.has_trigger)].filter(Boolean).join(", ") + "]" : "";
  const times = a.times > 1 ? ` ${a.times}×` : "";
  const picks = a.picks > 1 ? ` ${a.picks} ` : " ";
  let what = "";
  switch (a.effect) {
    case "buff": {
      const stats = [a.atk ? `+${a.atk} Angriff` : "", a.hp ? `+${a.hp} Leben` : "", a.value_from ? `+Angriff aus ${sch.value_from[a.value_from]}` : "", a.keyword ? kwName(a.keyword) : ""].filter(Boolean).join(", ");
      what = `${picks.trim() ? picks.trim() + " × " : ""}${tgt}${only} bekommt ${stats || "nichts"}${a.permanent ? " (dauerhaft)" : ""}`; break;
    }
    case "give_keyword": what = `${tgt}${only} bekommt ${a.keyword === "random" ? "ein zufälliges Schlüsselwort" : kwName(a.keyword)}${a.picks > 1 ? ` (${a.picks} Ziele)` : ""}`; break;
    case "remove_keyword": what = `${tgt} verliert ${(a.keywords || []).map(kwName).join(", ")}`; break;
    case "summon": what = `beschwöre ${a.random === "deathrattle" ? "zufällige Einheit mit Todesröcheln" : unitName(a.token)}${a.times > 1 ? ` (${a.times}×)` : ""}`; break;
    case "damage": what = `${a.value || 0}${a.value_from ? " + " + sch.value_from[a.value_from] : ""} Schaden an ${tgt}${only}`; break;
    case "destroy": what = `vernichte ${tgt}`; break;
    case "attack_now": what = "greift sofort an"; break;
    case "trigger_ability": what = `löse „${sch.triggers[a.ability_trigger] || a.ability_trigger}“ von ${tgt}${only} aus`; break;
    case "gold": what = `+${a.value || 0} Gold`; break;
    case "free_reroll": what = `+${a.value || 0} Gratis-Würfe`; break;
    default: what = a.effect;
  }
  const count = a.trigger === "avenge" ? ` (${a.count})` : "";
  return `${trig}${count}${when}:${a.effect === "buff" || a.effect === "give_keyword" ? "" : times} ${what}${a.effect === "buff" || a.effect === "give_keyword" ? times : ""}`;
}

function unitSummary(u) {
  const parts = (u.passives || []).map((p) => S.schema.passives[p] || p);
  return parts.concat((u.abilities || []).map(abilitySentence)).join(" · ");
}

// --- Einheiten ---

function unitMetrics(id) {
  return S.summary ? S.summary.units.find((x) => x.id === id) : null;
}

function renderUnits() {
  const el = $("#tab-units");
  const f = S.filters;
  const colors = RULES().colors || [];
  el.innerHTML = `
    <div class="filters">
      <input id="f-q" placeholder="Suchen (Name, Effekt, BG)" value="${esc(f.q)}">
      <select id="f-rarity"><option value="">alle Seltenheiten</option>${(RULES().rarities || []).map((r, i) => `<option value="${i}" ${String(i) === f.rarity ? "selected" : ""}>${esc(r)}</option>`).join("")}</select>
      <select id="f-color"><option value="">alle Farben</option>${colors.map((c) => `<option value="${esc(c.id)}" ${c.id === f.color ? "selected" : ""}>${esc(c.name)}</option>`).join("")}</select>
      <select id="f-status"><option value="">alle</option><option value="ok" ${f.status === "ok" ? "selected" : ""}>wie im Original</option><option value="simplified" ${f.status === "simplified" ? "selected" : ""}>vereinfacht</option></select>
      <select id="f-flag"><option value="">alle Werte</option><option value="any" ${f.flag === "any" ? "selected" : ""}>nur Warnungen</option></select>
      <span class="muted">${S.summary ? "Werte aus Lauf " + esc(S.runs.find((r) => r.has_report)?.run || "") : "Noch keine Simulation"}</span>
    </div>
    <div class="scroll"><table id="unit-table"></table></div>
    <div class="card" style="margin-top:14px"><h2>Spielsteine</h2><p class="muted">Werden beschworen, nicht gekauft.</p><div class="scroll"><table id="token-table"></table></div></div>`;
  ["q", "rarity", "color", "status", "flag"].forEach((k) => {
    const input = $("#f-" + k);
    input.addEventListener(k === "q" ? "input" : "change", () => { S.filters[k] = input.value; drawUnitTable(); });
  });
  drawUnitTable();
  drawTokenTable();
}

function drawUnitTable() {
  const f = S.filters;
  const q = f.q.toLowerCase();
  let rows = UNITS().map((u) => ({ u, m: unitMetrics(u.id) || {} }));
  rows = rows.filter(({ u, m }) =>
    (!q || [u.id, u.name, unitSummary(u), u.ref?.bg_name, u.ref?.bg_text].join(" ").toLowerCase().includes(q)) &&
    (f.rarity === "" || String(u.rarity) === f.rarity) && (!f.color || (u.colors || []).includes(f.color)) &&
    (!f.status || u.status === f.status) && (!f.flag || m.flag));
  const key = S.sort.key;
  const val = ({ u, m }) => (key in m && !(key in u) ? m[key] : u[key]);
  rows.sort((a, b) => { const x = val(a), y = val(b); return (x === y ? 0 : x === undefined || x === null ? 1 : y === undefined || y === null ? -1 : x > y ? 1 : -1) * S.sort.dir; });
  const cols = [["id", "Id"], ["name", "Name"], ["rarity", "Sel."], ["cost", "Preis", "num"], ["colors", "Farben"], ["atk", "A/L", "num"], ["keywords", "Schlüsselw."], ["eff", "Effekt"],
    ["winrate", "Winrate", "num"], ["vs_rarity", "± Sel.", "num"], ["pick_rate", "Pick %", "num"], ["battles", "Kämpfe", "num"], ["bg", "BG-Vorlage", "hide-mobile"]];
  const t = $("#unit-table");
  t.innerHTML = `<thead><tr>${cols.map(([k, l, c]) => `<th data-k="${k}" class="${c || ""}">${l}${S.sort.key === k ? (S.sort.dir > 0 ? " ▲" : " ▼") : ""}</th>`).join("")}</tr></thead><tbody>${rows.map(({ u, m }) => `
    <tr class="clickable ${m.flag ? "flag-" + m.flag : ""} ${u.disabled ? "disabled" : ""}" data-id="${esc(u.id)}">
      <td>${esc(u.id)}</td><td>${esc(u.name)}${u.status === "simplified" ? ' <span class="chip" title="vereinfacht">≈</span>' : ""}</td>
      <td>${esc(rarityName(u.rarity))}</td><td class="num">${u.cost}</td><td>${(u.colors || []).map(dot).join("")}</td>
      <td class="num">${u.atk}/${u.hp}</td><td>${(u.keywords || []).map((k) => `<span class="chip">${esc(kwName(k))}</span>`).join("")}</td>
      <td class="eff">${esc(unitSummary(u))}</td>
      <td class="num">${m.winrate ?? ""}</td><td class="num">${m.vs_rarity == null ? "" : (m.vs_rarity > 0 ? "+" : "") + m.vs_rarity}</td><td class="num">${m.pick_rate ?? ""}</td><td class="num">${m.battles ?? ""}</td>
      <td class="hide-mobile muted">${esc(u.ref?.bg_name || "")}</td></tr>`).join("")}</tbody>`;
  t.querySelectorAll("th").forEach((th) => th.addEventListener("click", () => {
    const k = th.dataset.k === "atk" ? "atk" : th.dataset.k;
    S.sort = { key: k, dir: S.sort.key === k ? -S.sort.dir : 1 };
    drawUnitTable();
  }));
  t.querySelectorAll("tr[data-id]").forEach((tr) => tr.addEventListener("click", () => openUnit(tr.dataset.id, false)));
}

function drawTokenTable() {
  $("#token-table").innerHTML = `<thead><tr><th>Id</th><th>Name</th><th>Farben</th><th class="num">A/L</th><th>Effekt</th></tr></thead><tbody>${TOKENS().map((u) => `
    <tr class="clickable" data-id="${esc(u.id)}"><td>${esc(u.id)}</td><td>${esc(u.name)}</td><td>${(u.colors || []).map(dot).join("")}</td>
    <td class="num">${u.atk}/${u.hp}</td><td class="eff">${esc(unitSummary(u))}</td></tr>`).join("")}</tbody>`;
  $("#token-table").querySelectorAll("tr[data-id]").forEach((tr) => tr.addEventListener("click", () => openUnit(tr.dataset.id, true)));
}

function openUnit(id, isToken) {
  const u = (isToken ? TOKENS() : UNITS()).find((x) => x.id === id);
  const p = $("#panel");
  p.hidden = false;
  const m = isToken ? null : unitMetrics(id);
  const sch = S.schema;
  const render = () => {
    p.innerHTML = `
      <button class="close" id="u-close">Schließen</button>
      <h2>${esc(u.id)} · ${esc(u.name)}</h2>
      <div class="muted">${isToken ? "Spielstein" : esc(rarityName(u.rarity)) + " · " + u.cost + " Gold"}</div>
      ${m ? `<div class="card" style="margin-top:8px"><span class="stat">Winrate <b>${m.winrate ?? "–"}</b></span><span class="stat">± Seltenheit ${m.vs_rarity ?? "–"}</span><span class="stat">früh ${m["winrate_früh"] ?? "–"}</span><span class="stat">mitte ${m.winrate_mitte ?? "–"}</span><span class="stat">spät ${m["winrate_spät"] ?? "–"}</span><br><span class="stat">Pick ${m.pick_rate ?? "–"} %</span><span class="stat">in ${m.presence ?? "–"} % der Kämpfe</span><span class="stat">Stufe 3: ${m.level3_share ?? "–"} %</span></div>` : ""}
      <div class="row">
        <label class="field"><span>Name</span><input data-f="name" value="${esc(u.name)}"></label>
        ${isToken ? "" : `<label class="field"><span>Seltenheit</span><select data-f="rarity">${(RULES().rarities || []).map((r, i) => `<option value="${i}" ${i === u.rarity ? "selected" : ""}>${esc(r)}</option>`).join("")}</select></label>
        <label class="field"><span>Preis</span><input type="number" min="0" step="5" data-f="cost" value="${u.cost}"></label>`}
        <label class="field"><span>Angriff</span><input type="number" min="0" data-f="atk" value="${u.atk}"></label>
        <label class="field"><span>Leben</span><input type="number" min="1" data-f="hp" value="${u.hp}"></label>
      </div>
      <div class="field"><span>Farben</span><div class="checks">${(RULES().colors || []).map((c) => `<label><input type="checkbox" data-color="${esc(c.id)}" ${(u.colors || []).includes(c.id) ? "checked" : ""}> ${dot(c.id)}${esc(c.name)}</label>`).join("")}</div></div>
      <div class="field"><span>Schlüsselwörter</span><div class="checks">${Object.entries(sch.keywords).map(([k, n]) => `<label><input type="checkbox" data-kw="${k}" ${(u.keywords || []).includes(k) ? "checked" : ""}> ${esc(n)}</label>`).join("")}</div></div>
      <div class="field"><span>Passive Wirkung</span><div class="checks">${Object.entries(sch.passives).map(([k, n]) => `<label><input type="checkbox" data-ps="${k}" ${(u.passives || []).includes(k) ? "checked" : ""}> ${esc(n)}</label>`).join("")}</div></div>
      ${isToken ? "" : `<label class="checks"><input type="checkbox" data-f="disabled" ${u.disabled ? "checked" : ""}> nicht im Shop anbieten</label>`}
      <h3>Fähigkeiten</h3>
      <div id="u-abilities"></div>
      <div class="row"><button id="u-add" class="small">+ Fähigkeit</button><button id="u-json" class="small">Als JSON bearbeiten</button></div>
      ${u.ref ? `<div class="ref"><b>Vorlage:</b> ${esc(u.ref.bg_name)} (BG Stufe ${esc(u.ref.bg_tier)}, ${esc((u.ref.bg_races || []).join("/") || "neutral")})<br>${esc(u.ref.bg_text)}<br><span class="muted">Platz: ${esc(u.ref.slot_name)} · Status: ${esc(u.status)}${u.note ? " · " + esc(u.note) : ""}</span></div>` : ""}`;
    p.querySelector("#u-close").onclick = () => { p.hidden = true; drawUnitTable(); drawTokenTable(); };
    p.querySelectorAll("[data-f]").forEach((inp) => inp.addEventListener("change", () => {
      const k = inp.dataset.f;
      if (inp.type === "checkbox") { if (inp.checked) u[k] = true; else delete u[k]; }
      else u[k] = ["rarity", "cost", "atk", "hp"].includes(k) ? parseInt(inp.value || "0", 10) : inp.value;
      markDirty();
    }));
    p.querySelectorAll("[data-color]").forEach((cb) => cb.addEventListener("change", () => {
      u.colors = [...p.querySelectorAll("[data-color]:checked")].map((x) => x.dataset.color); markDirty();
    }));
    p.querySelectorAll("[data-kw]").forEach((cb) => cb.addEventListener("change", () => {
      u.keywords = [...p.querySelectorAll("[data-kw]:checked")].map((x) => x.dataset.kw); markDirty();
    }));
    p.querySelectorAll("[data-ps]").forEach((cb) => cb.addEventListener("change", () => {
      u.passives = [...p.querySelectorAll("[data-ps]:checked")].map((x) => x.dataset.ps); markDirty();
    }));
    p.querySelector("#u-add").onclick = () => { (u.abilities = u.abilities || []).push({ trigger: "start_of_combat", effect: "buff", target: "self", atk: 1 }); markDirty(); drawAbilities(u); };
    p.querySelector("#u-json").onclick = () => editAbilitiesJson(u, render);
    drawAbilities(u);
  };
  render();
}

const NUM_FIELDS = ["atk", "hp", "value", "times", "picks", "count"];

function fieldsFor(a) {
  const f = ["trigger", "effect"];
  const targeted = !["summon", "attack_now", "gold", "free_reroll"].includes(a.effect);
  if (targeted) f.push("target");
  if (a.trigger === "avenge") f.push("count");
  if (["on_ally_death", "on_summon", "on_ally_attack", "on_reborn", "after_deathrattle", "on_ally_shield_lost", "on_ally_buy", "after_battlecry"].includes(a.trigger)) f.push("when");
  if (a.trigger === "on_ally_attack") f.push("include_self");
  ({
    buff: ["atk", "hp", "value_from", "keyword", "permanent", "only", "times", "picks"],
    give_keyword: ["keyword", "permanent", "only", "picks"],
    remove_keyword: ["keywords"],
    summon: ["token", "times"],
    damage: ["value", "value_from", "only", "picks", "times"],
    destroy: ["only"],
    trigger_ability: ["ability_trigger", "only"],
    gold: ["value"], free_reroll: ["value"],
  }[a.effect] || []).forEach((x) => f.push(x));
  return f;
}

function drawAbilities(u) {
  const box = $("#u-abilities");
  const sch = S.schema;
  const opt = (obj, cur, empty) => (empty ? `<option value="">${empty}</option>` : "") + Object.entries(obj).map(([k, n]) => `<option value="${esc(k)}" ${k === cur ? "selected" : ""}>${esc(n)}</option>`).join("");
  const colors = Object.fromEntries((RULES().colors || []).map((c) => [c.id, c.name]));
  const tokens = Object.fromEntries(TOKENS().map((t) => [t.id, t.name]));
  box.innerHTML = (u.abilities || []).map((a, i) => {
    const f = fieldsFor(a);
    const input = (k) => {
      switch (k) {
        case "trigger": return `<label class="field"><span>Auslöser</span><select data-k="trigger">${opt(sch.triggers, a.trigger)}</select></label>`;
        case "effect": return `<label class="field"><span>Effekt</span><select data-k="effect">${opt(Object.fromEntries(Object.keys(sch.effects).map((e) => [e, e])), a.effect)}</select></label>`;
        case "target": return `<label class="field"><span>Ziel</span><select data-k="target">${opt(sch.targets, a.target || "self")}</select></label>`;
        case "keyword": return `<label class="field"><span>Schlüsselwort</span><select data-k="keyword">${opt({ ...(a.effect === "give_keyword" ? { random: "zufällig" } : {}), ...sch.keywords }, a.keyword, "–")}</select></label>`;
        case "keywords": return `<label class="field"><span>Schlüsselwörter (Komma)</span><input data-k="keywords" value="${esc((a.keywords || []).join(","))}"></label>`;
        case "value_from": return `<label class="field"><span>plus Wert aus</span><select data-k="value_from">${opt(sch.value_from, a.value_from, "–")}</select></label>`;
        case "token": return `<label class="field"><span>Beschwört</span><select data-k="token">${opt({ ...tokens, "random:deathrattle": "zufällige Einheit mit Todesröcheln" }, a.random === "deathrattle" ? "random:deathrattle" : a.token)}</select></label>`;
        case "ability_trigger": return `<label class="field"><span>Welche Fähigkeit</span><select data-k="ability_trigger">${opt(sch.triggers, a.ability_trigger)}</select></label>`;
        case "permanent": return `<label class="field"><span>dauerhaft</span><input type="checkbox" data-k="permanent" ${a.permanent ? "checked" : ""}></label>`;
        case "include_self": return `<label class="field"><span>auch selbst</span><input type="checkbox" data-k="include_self" ${a.include_self ? "checked" : ""}></label>`;
        case "only": return `<label class="field"><span>nur Ziele mit Farbe</span><select data-k="only.color">${opt(colors, a.only?.color, "alle")}</select></label>`;
        case "when": return `<label class="field"><span>nur wenn Auslöser Farbe</span><select data-k="when.color">${opt(colors, a.when?.color, "egal")}</select></label>`;
        default: return `<label class="field"><span>${{ atk: "Angriff", hp: "Leben", value: "Wert", times: "Wiederholungen", picks: "Anzahl Ziele", count: "Tode" }[k]}</span><input type="number" data-k="${k}" value="${a[k] ?? ""}"></label>`;
      }
    };
    const extra = (a.only && (a.only.keyword || a.only.has_trigger)) || (a.when && a.when.has_trigger) ? `<div class="muted">Weitere Filter nur über JSON: ${esc(JSON.stringify({ only: a.only, when: a.when }))}</div>` : "";
    return `<div class="ability" data-i="${i}"><div class="sentence">${esc(abilitySentence(a))}</div><div class="grid">${f.map(input).join("")}</div>${extra}
      <div class="row"><button class="small danger" data-del="${i}">Entfernen</button></div></div>`;
  }).join("") || '<p class="muted">Keine Fähigkeiten.</p>';
  box.querySelectorAll(".ability").forEach((div) => {
    const a = u.abilities[+div.dataset.i];
    div.querySelectorAll("[data-k]").forEach((inp) => inp.addEventListener("change", () => {
      const k = inp.dataset.k;
      if (k === "only.color" || k === "when.color") {
        const base = k.split(".")[0];
        a[base] = { ...(a[base] || {}) };
        if (inp.value) a[base].color = inp.value; else delete a[base].color;
        if (!Object.keys(a[base]).length) delete a[base];
      } else if (k === "token") {
        if (inp.value === "random:deathrattle") { a.random = "deathrattle"; delete a.token; } else { a.token = inp.value; delete a.random; }
      } else if (k === "keywords") {
        a.keywords = inp.value.split(",").map((s) => s.trim()).filter(Boolean);
      } else if (inp.type === "checkbox") {
        if (inp.checked) a[k] = true; else delete a[k];
      } else if (NUM_FIELDS.includes(k)) {
        if (inp.value === "") delete a[k]; else a[k] = parseInt(inp.value, 10);
      } else if (inp.value === "") {
        delete a[k];
      } else {
        a[k] = inp.value;
      }
      markDirty();
      drawAbilities(u);
    }));
  });
  box.querySelectorAll("[data-del]").forEach((b) => b.addEventListener("click", () => { u.abilities.splice(+b.dataset.del, 1); markDirty(); drawAbilities(u); }));
}

function editAbilitiesJson(u, after) {
  const box = openModal(`<h2>Fähigkeiten als JSON</h2><p class="muted">Felder siehe Hilfe. Wird beim Speichern geprüft.</p>
    <textarea id="aj" style="min-height:300px;font-family:ui-monospace,monospace;font-size:12px">${esc(JSON.stringify(u.abilities || [], null, 1))}</textarea>
    <div class="row"><button class="primary" id="aj-ok">Übernehmen</button><button id="aj-cancel">Abbrechen</button><span id="aj-err" class="muted"></span></div>`);
  box.querySelector("#aj-cancel").onclick = closeModal;
  box.querySelector("#aj-ok").onclick = () => {
    try {
      const v = JSON.parse($("#aj").value);
      if (!Array.isArray(v)) throw new Error("Erwartet eine Liste");
      u.abilities = v; markDirty(); closeModal(); after();
    } catch (e) { box.querySelector("#aj-err").textContent = e.message; }
  };
}

// --- Shop und Wirtschaft ---

function numInput(path, label, attrs = "") {
  return `<label class="field"><span>${label}</span><input type="number" data-path="${path}" value="${esc(getPath(path))}" ${attrs}></label>`;
}
function listInput(path, label) {
  return `<label class="field"><span>${label}</span><input data-list="${path}" value="${esc((getPath(path) || []).join(", "))}" style="width:260px"></label>`;
}
function getPath(path) { return path.split(".").reduce((o, k) => (o == null ? o : o[k]), RULES()); }
function setPath(path, value) {
  const keys = path.split(".");
  let o = RULES();
  keys.slice(0, -1).forEach((k) => { o[k] = o[k] || {}; o = o[k]; });
  o[keys[keys.length - 1]] = value;
}
function bindInputs(root) {
  root.querySelectorAll("[data-path]").forEach((inp) => inp.addEventListener("change", () => {
    if (inp.type === "checkbox") setPath(inp.dataset.path, inp.checked);
    else if (inp.type === "number") setPath(inp.dataset.path, parseInt(inp.value || "0", 10));
    else setPath(inp.dataset.path, inp.value);
    markDirty();
    if (inp.dataset.rerender) renderAll();
  }));
  root.querySelectorAll("[data-list]").forEach((inp) => inp.addEventListener("change", () => {
    setPath(inp.dataset.list, inp.value.split(/[,;\s]+/).filter(Boolean).map((x) => parseInt(x, 10)).filter((x) => !isNaN(x)));
    markDirty();
  }));
}

function renderShop() {
  const el = $("#tab-shop");
  const r = RULES();
  const rar = r.rarities || [];
  const table = r.shop.rarity_weights_by_rank;
  const prices = rar.map((_, i) => { const us = UNITS().filter((u) => u.rarity === i && !u.disabled); return { n: us.length, avg: us.length ? Math.round(us.reduce((s, u) => s + u.cost, 0) / us.length) : 0, min: Math.min(...us.map((u) => u.cost)), max: Math.max(...us.map((u) => u.cost)) }; });
  const income = Array.from({ length: 12 }, (_, i) => { const d = i + 1; const l = r.economy.income_by_day; return d <= l.length ? l[d - 1] : l[l.length - 1] + (d - l.length) * (r.economy.income_growth_after || 0); });
  el.innerHTML = `
    <div class="card"><h2>Wirtschaft</h2>
      <div class="row">${listInput("economy.income_by_day", "Einkommen je Tag (Liste)")}${numInput("economy.income_growth_after", "danach + je Tag")}
      ${numInput("economy.reroll_cost", "Neu würfeln kostet")}${numInput("economy.free_rerolls_per_day", "Gratis-Würfe je Tag")}
      <label class="field"><span>Gold bleibt erhalten</span><input type="checkbox" data-path="economy.gold_carries_over" ${r.economy.gold_carries_over ? "checked" : ""}></label></div>
      <div class="muted">Einkommen Tag 1 bis 12: ${income.join(", ")}. ${esc(r.economy.income_note || "")}</div>
      <div class="row">${listInput("economy.sell_level_multiplier", "Verkauf: Faktor je Stufe")}${numInput("economy.sell_divisor", "geteilt durch")}</div>
      <div class="muted">Verkaufswert = aufgerundet(Preis × Faktor ÷ Teiler). Bei 20 Gold: Stufe 1 = ${Math.ceil(20 * (r.economy.sell_level_multiplier[0] || 1) / r.economy.sell_divisor)}, Stufe 2 = ${Math.ceil(20 * (r.economy.sell_level_multiplier[1] || 1) / r.economy.sell_divisor)}, Stufe 3 = ${Math.ceil(20 * (r.economy.sell_level_multiplier[2] || 1) / r.economy.sell_divisor)}.</div>
    </div>
    <div class="card"><h2>Angebot</h2>
      <div class="row">${numInput("shop.slots", "Plätze im Shop")}${numInput("shop.rank_start", "Rang an Tag 1")}${numInput("shop.rank_per_day", "Rang + je Tag")}
      <label class="field"><span>Maximal-Stufe nicht mehr anbieten</span><input type="checkbox" data-path="shop.exclude_owned_max_level" ${r.shop.exclude_owned_max_level ? "checked" : ""}></label></div>
      <h3>Seltenheitschancen je Shop-Rang</h3>
      <p class="muted">Gewichte je Zeile, werden auf 100 % gerechnet. Der Rang steigt jeden Tag. Letzte Zeile gilt für alle höheren Ränge.</p>
      <div class="scroll"><table class="odds"><thead><tr><th>Rang</th>${rar.map((x) => `<th class="num">${esc(x)}</th>`).join("")}<th class="num">Summe</th><th></th></tr></thead><tbody>
      ${table.map((row, i) => { const sum = row.reduce((a, b) => a + b, 0); return `<tr><td>${i + 1}${i === table.length - 1 ? "+" : ""}</td>${row.map((v, j) => `<td class="num"><input type="number" min="0" data-odds="${i},${j}" value="${v}"></td>`).join("")}<td class="num ${sum <= 0 ? "bad" : ""}">${sum}</td><td><button class="small" data-del-rank="${i}">−</button></td></tr>`; }).join("")}
      </tbody></table></div>
      <button class="small" id="add-rank">+ Rang</button>
      <h3>Preise nach Seltenheit</h3>
      <table><thead><tr><th>Seltenheit</th><th class="num">Einheiten</th><th class="num">Preis Schnitt</th><th class="num">min</th><th class="num">max</th></tr></thead><tbody>
      ${prices.map((p, i) => `<tr><td>${esc(rar[i])}</td><td class="num">${p.n}</td><td class="num">${p.avg}</td><td class="num">${p.n ? p.min : ""}</td><td class="num">${p.n ? p.max : ""}</td></tr>`).join("")}</tbody></table>
    </div>`;
  bindInputs(el);
  el.querySelectorAll("[data-odds]").forEach((inp) => inp.addEventListener("change", () => {
    const [i, j] = inp.dataset.odds.split(",").map(Number);
    table[i][j] = Math.max(0, parseInt(inp.value || "0", 10));
    markDirty(); renderShop();
  }));
  el.querySelectorAll("[data-del-rank]").forEach((b) => b.addEventListener("click", () => { if (table.length > 1) { table.splice(+b.dataset.delRank, 1); markDirty(); renderShop(); } }));
  $("#add-rank").onclick = () => { table.push(clone(table[table.length - 1])); markDirty(); renderShop(); };
}

// --- Regeln ---

function renderRules() {
  const el = $("#tab-rules");
  const r = RULES();
  el.innerHTML = `
    <div class="card"><h2>Run</h2><div class="row">
      ${numInput("run.start_lives", "Startleben")}${numInput("run.wins_to_victory", "Siege bis Ende")}${numInput("run.max_days", "maximal Tage")}
      ${listInput("run.life_loss_by_day", "Lebensverlust je Tag (Liste)")}
      <label class="field"><span>Second Chance</span><input type="checkbox" data-path="run.second_chance" ${r.run.second_chance ? "checked" : ""}></label>
      <label class="field"><span>Unentschieden zählt als</span><select data-path="run.draw_result">${["win", "draw", "loss"].map((v) => `<option value="${v}" ${r.run.draw_result === v ? "selected" : ""}>${{ win: "Sieg (Batomon)", draw: "Unentschieden", loss: "Niederlage" }[v]}</option>`).join("")}</select></label>
    </div></div>
    <div class="card"><h2>Gegner (Schwierigkeit)</h2>
      <p class="muted">Gegner sind gespeicherte Teams aus den Bot-Läufen (Geister). Hier stellst du ein, welche davon du triffst. Wirkt nach dem nächsten Test-Build bzw. der nächsten Simulation.</p>
      <div class="row">
        <div class="field"><span>Geister von diesen Bots</span><div class="checks">${["random", "greedy", "synergy"].map((b) => `<label><input type="checkbox" data-ghostbot="${b}" ${(r.run.ghost_bots || []).includes(b) ? "checked" : ""}> ${{ random: "Zufall", greedy: "Gier", synergy: "Synergie" }[b]}</label>`).join("")}</div><span>keiner angehakt = alle</span></div>
        ${numInput("run.ghost_match_pool", "Passend zur Siegzahl: aus den N ähnlichsten (0 = aus)")}
        ${numInput("run.ghost_day_offset", "Gegner vom Tag + (0 = gleicher Tag)")}
      </div></div>
    <div class="card"><h2>Brett und Stufen</h2><div class="row">
      ${numInput("board.team_slots", "Teamplätze")}${numInput("board.bench_slots", "Bankplätze")}${numInput("board.max_level", "höchste Stufe")}
      ${listInput("board.merge_counts", "Kopien zum Verschmelzen je Stufe")}${listInput("board.level_scale", "Wertefaktor je Stufe")}
      <label class="field"><span>Boni beim Verschmelzen</span><select data-path="board.merge_bonus"><option value="max" ${r.board.merge_bonus === "max" ? "selected" : ""}>stärkster bleibt (Batomon)</option><option value="sum" ${r.board.merge_bonus === "sum" ? "selected" : ""}>addieren (BG)</option></select></label>
    </div></div>
    <div class="card"><h2>Kampf</h2><div class="row">
      <label class="field"><span>Regeln</span><select data-path="combat.mode" data-rerender="1"><option value="bg" ${r.combat.mode === "bg" ? "selected" : ""}>BG: Reihe, abwechselnd, Gegenschlag</option><option value="grid" ${r.combat.mode === "grid" ? "selected" : ""}>Raster: vordere Reihe zuerst, kein Gegenschlag</option></select></label>
      ${numInput("combat.bg.max_units", "BG: max. Einheiten im Kampf")}${numInput("combat.bg.max_attacks", "BG: max. Angriffe")}
      ${numInput("combat.grid.cols", "Raster: Spalten")}${numInput("combat.grid.rows", "Raster: Reihen")}${numInput("combat.grid.max_ticks", "Raster: max. Ticks")}
    </div><p class="muted">Im Raster sind Platz 0 bis Spalten−1 die vordere Reihe.</p></div>
    <div class="card"><h2>Simulation und Bots</h2><div class="row">
      ${numInput("sim.ghosts_per_day", "Geisterteams je Tag")}${numInput("bots.max_actions_per_day", "Bot-Aktionen je Tag")}
      ${numInput("bots.random_reroll_percent", "Zufallsbot würfelt neu (%)")}${numInput("bots.greedy_reroll_min_gold", "andere Bots würfeln ab Gold")}
    </div></div>`;
  bindInputs(el);
  el.querySelectorAll("[data-ghostbot]").forEach((cb) => cb.addEventListener("change", () => {
    r.run.ghost_bots = [...el.querySelectorAll("[data-ghostbot]:checked")].map((x) => x.dataset.ghostbot);
    markDirty();
  }));
}

// --- Simulation ---

function renderSim() {
  const el = $("#tab-sim");
  const runs = S.runs.filter((r) => r.has_report);
  el.innerHTML = `
    <div class="card"><h2>Simulation starten</h2>
      <p class="muted">Bots spielen komplette Runs gegen Geisterteams. Geister-Durchgänge erzeugen die Gegner vorher neu aus dem aktuellen Stand (nach Änderungen empfohlen: 2). 900 Runs mit 2 Geister-Durchgängen dauern etwa 2 Minuten.</p>
      <div class="row">
        <label class="field"><span>Runs</span><input type="number" id="sim-runs" value="900" min="30" step="300"></label>
        <label class="field"><span>Geister-Durchgänge</span><input type="number" id="sim-ghosts" value="2" min="0" max="5"></label>
        <label class="field"><span>Kampf</span><select id="sim-combat"><option value="">wie im Regelsatz (${esc(RULES().combat.mode)})</option><option value="bg">BG</option><option value="grid">Raster</option></select></label>
        <label class="field"><span>Seed</span><input type="number" id="sim-seed" value="1"></label>
        <button class="primary" id="sim-go" ${isDirty() ? "disabled title='Erst speichern'" : ""}>Starten</button>
      </div>
      ${isDirty() ? '<p class="muted">Ungespeicherte Änderungen: erst speichern, damit die Simulation den neuen Stand nutzt.</p>' : ""}
      <div id="job-box"></div>
    </div>
    <div class="card"><h2>Selbst spielen</h2>
      <p class="muted">Baut einen Test-Build mit dem gespeicherten Stand (etwa 15 Sekunden) und öffnet ihn im Browser, auch auf dem Handy. Die Gegner sind die Geisterteams der letzten Simulation.</p>
      <div class="row">
        <button id="play-build" ${isDirty() ? "disabled title='Erst speichern'" : ""}>Test-Build bauen</button>
        ${S.playBuilt ? `<a class="primary" href="play/${esc(S.name)}/index.html" target="_blank" rel="noopener"><button class="primary">Spielen</button></a><span class="muted">gebaut ${esc(S.playBuilt.replace("T", " "))}</span>` : '<span class="muted">Noch kein Test-Build.</span>'}
      </div>
    </div>
    <div class="card"><h2>Läufe</h2>
      ${runs.length ? `<div class="scroll"><table><thead><tr><th>Lauf</th><th class="num">Version</th><th>Kampf</th><th class="num">Runs</th><th class="num">Siege gier</th><th class="num">Siege synergie</th><th class="num">Siege zufall</th><th class="num">Unent. %</th><th>A</th><th>B</th><th></th></tr></thead><tbody>
      ${runs.map((r) => { const g = r.groups || {}; return `<tr><td>${esc(r.run)}</td><td class="num">${esc(r.meta.version ?? "")}</td><td>${esc(r.meta.params?.combat || "Regelsatz")}</td><td class="num">${r.overall?.runs ?? ""}</td>
        <td class="num">${g.greedy?.avg_wins ?? ""}</td><td class="num">${g.synergy?.avg_wins ?? ""}</td><td class="num">${g.random?.avg_wins ?? ""}</td><td class="num">${r.overall?.draw_rate ?? ""}</td>
        <td><input type="radio" name="cmp-a" value="${esc(r.run)}" ${S.compare.a === r.run ? "checked" : ""}></td><td><input type="radio" name="cmp-b" value="${esc(r.run)}" ${S.compare.b === r.run ? "checked" : ""}></td>
        <td><a href="runs/${esc(S.name)}/${esc(r.run)}/report.html" target="_blank" rel="noopener">Bericht</a></td></tr>`; }).join("")}
      </tbody></table></div><p class="muted">A = vorher, B = nachher. Dann unten vergleichen.</p>` : '<p class="muted">Noch keine Läufe.</p>'}
    </div>
    <div class="card" id="cmp-box"><h2>Vergleich</h2><p class="muted">Zwei Läufe als A und B wählen.</p></div>`;
  $("#sim-go").onclick = startSim;
  $("#play-build").onclick = async () => {
    try { await api("build_play/" + S.name, {}); toast("Test-Build wird gebaut"); pollJob(); } catch (e) { toast(e.message); }
  };
  el.querySelectorAll("input[name=cmp-a],input[name=cmp-b]").forEach((r) => r.addEventListener("change", () => {
    S.compare[r.name === "cmp-a" ? "a" : "b"] = r.value; drawCompare();
  }));
  drawJob();
  drawCompare();
}

async function startSim() {
  try {
    await api("simulate/" + S.name, { runs: +$("#sim-runs").value, ghosts: +$("#sim-ghosts").value, combat: $("#sim-combat").value, seed: +$("#sim-seed").value });
    toast("Simulation gestartet");
    pollJob();
  } catch (e) { toast(e.message); }
}

async function pollJob() {
  clearTimeout(S.poll);
  try {
    const { job } = await api("job");
    const wasRunning = S.job && S.job.state === "läuft";
    S.job = job;
    drawJob();
    if (job && job.state === "läuft") S.poll = setTimeout(pollJob, 2000);
    else if (wasRunning && job && job.ruleset === S.name && job.kind === "play") {
      S.playBuilt = (await api("ruleset/" + S.name)).play_built;
      renderSim();
      toast(job.state === "fertig" ? "Test-Build fertig, jetzt auf Spielen tippen" : "Test-Build fehlgeschlagen");
    } else if (wasRunning && job && job.ruleset === S.name) {
      await loadRuns();
      if (job.state === "fertig") { S.compare.b = job.run; if (!S.compare.a) S.compare.a = (S.runs.filter((r) => r.has_report)[1] || {}).run || ""; }
      renderUnits(); renderSim();
      toast(job.state === "fertig" ? "Simulation fertig" : "Simulation fehlgeschlagen");
    }
  } catch (e) { /* Server kurz weg */ }
}

function drawJob() {
  const box = $("#job-box");
  if (!box) return;
  const j = S.job;
  if (!j) { box.innerHTML = ""; return; }
  const secs = Math.round(Date.now() / 1000 - j.started);
  box.innerHTML = `<p><b>${esc(j.ruleset)}</b> · ${esc(j.state)} · ${esc(j.step)}${j.state === "läuft" ? ` · ${secs} s` : ""}</p><div class="log-box">${esc((j.log || []).join("\n"))}</div>`;
}

async function drawCompare() {
  const box = $("#cmp-box");
  if (!box || !S.compare.a || !S.compare.b) return;
  const [A, B] = await Promise.all([summaryOf(S.compare.a), summaryOf(S.compare.b)]);
  const ua = Object.fromEntries(A.units.map((u) => [u.id, u]));
  // Standardfehler einer Siegquote: höchstens 50 / Wurzel(n) Prozentpunkte. z ab 2 gilt als echte Änderung.
  const se = (n) => (n > 0 ? 50 / Math.sqrt(n) : Infinity);
  const rows = B.units.map((u) => {
    const a = ua[u.id] || {};
    const d = u.winrate != null && a.winrate != null ? +(u.winrate - a.winrate).toFixed(1) : null;
    const enough = (a.battles || 0) >= 30 && (u.battles || 0) >= 30;
    const z = d == null ? 0 : d / Math.hypot(se(a.battles || 0), se(u.battles || 0));
    return { u, a, d, enough, z };
  }).sort((x, y) => (y.enough - x.enough) || Math.abs(y.z) - Math.abs(x.z));
  const groups = Object.keys(B.groups || {});
  const delta = (v) => (v == null ? "" : `<span class="${v > 0 ? "delta-pos" : v < 0 ? "delta-neg" : ""}">${v > 0 ? "+" : ""}${v}</span>`);
  box.innerHTML = `<h2>Vergleich ${esc(S.compare.a)} → ${esc(S.compare.b)}</h2>
    <table><thead><tr><th>Gruppe</th><th class="num">Siege A</th><th class="num">Siege B</th><th class="num">Δ</th><th class="num">10 Siege % A</th><th class="num">B</th></tr></thead><tbody>
    ${groups.map((g) => { const a = A.groups[g] || {}, b = B.groups[g] || {}; return `<tr><td>${esc(g)}</td><td class="num">${a.avg_wins ?? ""}</td><td class="num">${b.avg_wins ?? ""}</td><td class="num">${delta(a.avg_wins != null ? +(b.avg_wins - a.avg_wins).toFixed(2) : null)}</td><td class="num">${a.victory_rate ?? ""}</td><td class="num">${b.victory_rate ?? ""}</td></tr>`; }).join("")}
    </tbody></table>
    <p class="muted">Sortiert nach Sicherheit der Änderung. <b>Fett</b> = größer als zwei Standardfehler, also sehr wahrscheinlich echt. Grau = unter 30 Kämpfe, nur Rauschen. Mehr Runs machen den Vergleich genauer.</p>
    <div class="scroll"><table><thead><tr><th>Id</th><th>Name</th><th class="num">Preis</th><th class="num">Winrate A</th><th class="num">Winrate B</th><th class="num">Δ</th><th class="num">Pick A</th><th class="num">Pick B</th><th class="num">Kämpfe B</th></tr></thead><tbody>
    ${rows.map(({ u, a, d, enough, z }) => `<tr class="${u.flag ? "flag-" + u.flag : ""}" style="${enough ? "" : "opacity:.45"}"><td>${esc(u.id)}</td><td>${esc(u.name)}</td><td class="num">${u.cost}</td><td class="num">${a.winrate ?? ""}</td><td class="num">${u.winrate ?? ""}</td><td class="num">${Math.abs(z) >= 2 && enough ? "<b>" + delta(d) + "</b>" : delta(d)}</td><td class="num">${a.pick_rate ?? ""}</td><td class="num">${u.pick_rate ?? ""}</td><td class="num">${u.battles}</td></tr>`).join("")}
    </tbody></table></div>`;
}

// --- Protokoll ---

async function renderLog() {
  const el = $("#tab-log");
  if (!S.name) return;
  const { entries } = await api("changelog/" + S.name);
  el.innerHTML = `<div class="card"><h2>Balance-Protokoll</h2><p class="muted">Jede gespeicherte Änderung mit Notiz, Vorhersage und Ergebnis. „Zurücksetzen“ stellt den Stand vor dieser Änderung wieder her (als neue Version).</p></div>
    ${entries.slice().reverse().map((e) => `<div class="card"><div class="row"><b>Version ${esc(e.version)}</b><span class="muted">${esc(e.id)}</span><button class="small" data-restore="${esc(e.id)}">Zurücksetzen</button></div>
      <div><b>Was:</b> ${esc(e.note) || '<span class="muted">keine Notiz</span>'}</div>
      <div><b>Vorhersage:</b> ${esc(e.prediction) || '<span class="muted">keine</span>'}</div>
      <ul class="changes">${(e.changes || []).map((c) => `<li>${esc(c)}</li>`).join("")}</ul>
      <label class="field"><span>Ergebnis (nach der Simulation)</span><textarea data-result="${esc(e.id)}" placeholder="Eingetroffen? Was ist wirklich passiert?">${esc(e.result)}</textarea></label>
      <button class="small" data-save-result="${esc(e.id)}">Ergebnis speichern</button></div>`).join("") || '<p class="muted">Noch keine Änderungen gespeichert.</p>'}`;
  el.querySelectorAll("[data-save-result]").forEach((b) => b.addEventListener("click", async () => {
    await api(`changelog/${S.name}/result`, { id: b.dataset.saveResult, result: el.querySelector(`[data-result="${b.dataset.saveResult}"]`).value });
    toast("Ergebnis gespeichert");
  }));
  el.querySelectorAll("[data-restore]").forEach((b) => b.addEventListener("click", async () => {
    if (isDirty()) { toast("Erst speichern oder verwerfen"); return; }
    if (!confirm("Stand vor dieser Änderung wiederherstellen?")) return;
    await api(`changelog/${S.name}/restore`, { id: b.dataset.restore });
    await loadRuleset(S.name);
    toast("Zurückgesetzt");
  }));
}

// --- Hilfe ---

function renderHelp() {
  const sch = S.schema;
  $("#tab-help").innerHTML = `
    <div class="card"><h2>So übst du Balancing hier</h2><ol>
      <li><b>Lauf als Ausgangslage:</b> Simulation starten (900 Runs, 2 Geister-Durchgänge). Das ist A.</li>
      <li><b>Problem suchen:</b> In „Einheiten“ nach „± Sel.“ sortieren oder „nur Warnungen“ filtern. Rot = stärker als ihre Seltenheit, blau = schwächer.</li>
      <li><b>Hypothese:</b> Warum? Preis zu niedrig, Werte zu hoch, Effekt zu stark, Farbe zu stark?</li>
      <li><b>Eine Sache ändern</b> und mit Notiz und Vorhersage speichern. Nicht mehrere Dinge auf einmal, sonst weißt du nicht, was gewirkt hat.</li>
      <li><b>Neuer Lauf</b> (B), dann unter „Simulation“ A und B vergleichen.</li>
      <li><b>Ergebnis eintragen</b> im Protokoll: War die Vorhersage richtig? Die Treffsicherheit deiner Vorhersagen ist das, was du übst.</li>
    </ol>
    <p class="muted">Regler, die du hast: Preis und Seltenheit (Shop-Seite), Werte und Effekte (Einheit), Chancentabelle und Einkommen (Wirtschaft), Kampfregeln (Regeln). Mit „Kopie“ probierst du Varianten aus, ohne den Hauptstand zu verändern.</p></div>
    <div class="card"><h2>Kennzahlen</h2><ul>
      <li><b>Winrate</b>: Siegquote der Kämpfe, in denen die Einheit im Team stand, bereinigt um den Tagesschnitt. 50 = durchschnittlich.</li>
      <li><b>± Sel.</b>: Abstand zum Schnitt der eigenen Seltenheit. Höhere Seltenheiten dürfen stärker sein, sie kosten mehr. Rot/blau ab 8 Punkten Abstand und 80 Kämpfen.</li>
      <li><b>früh/mitte/spät</b>: Tage 1 bis 3, 4 bis 7, ab 8.</li>
      <li><b>Pick %</b>: wie oft Bots sie kaufen, wenn sie angeboten wird. Bots kaufen nach Preis, Verschmelzen und Farbe, nicht nach Effekt.</li>
      <li><b>BG-Abgleich</b> (im Bericht): Rangkorrelation unserer Winrate mit dem echten BG-Durchschnittsplatz der Vorlage.</li>
    </ul></div>
    <div class="card"><h2>Bausteine für Fähigkeiten</h2>
      <h3>Auslöser</h3><ul>${Object.entries(sch.triggers).map(([k, v]) => `<li><code>${k}</code>: ${esc(v)}${sch.shop_triggers.includes(k) ? " (Shop)" : ""}</li>`).join("")}</ul>
      <h3>Effekte</h3><ul>${Object.entries(sch.effects).map(([k, v]) => `<li><code>${k}</code>: ${esc(v)}</li>`).join("")}</ul>
      <h3>Ziele</h3><ul>${Object.entries(sch.targets).map(([k, v]) => `<li><code>${k}</code>: ${esc(v)}</li>`).join("")}</ul>
      <p class="muted">Werte in atk, hp, value und times wachsen mit der Stufe (Wertefaktor je Stufe). Beschworene Spielsteine bekommen die Stufe der Beschwörerin. Shop-Effekte wirken immer dauerhaft, Kampf-Effekte nur mit „dauerhaft“.</p></div>`;
}

init().catch((e) => { document.body.insertAdjacentHTML("beforeend", `<p style="padding:16px;color:#b3261e">Fehler beim Laden: ${esc(e.message)}</p>`); });
