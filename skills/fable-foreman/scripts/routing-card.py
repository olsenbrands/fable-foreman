#!/usr/bin/env python3
"""fable-foreman — the routing card: THE answer to "which seat for this job", on this machine, today.

Joins, deterministically:
  1. what is live here   — probe.sh output (run automatically) + optional access-check.sh output
  2. what is consented   — the probe's pre-approval lines, plus --consented for in-session consent
  3. the suggestions     — references/routing-defaults.json (settled rows vs close calls)
  4. what was learned    — $FOREMAN_HOME/recon/models.json verdicts (with expiry) and
                           $FOREMAN_HOME/session-prefs.md (the user's close-call answers)

Usage:
  routing-card.py [build] [--probe-output F] [--access F] [--session ID] [--project DIR] [--consented codex,grok]
      Prints the card (and the probe output it used) and caches it at $FOREMAN_HOME/routing-card.md.
      --session: the ledger's run id, so answers given earlier in THIS session are applied, not re-asked.
  routing-card.py remember <job-id> <choice|judgment> --session ID [--project DIR]
  routing-card.py recon-record <provider> <model> <use|trial|ignore> <job-ids,comma|-> <valid-days> <note...>
      Saves a recon verdict so the same model is not researched again until it expires.
  routing-card.py approve-premium <model> --session ID --confirmed
      Records the user's DOUBLE approval of a premium seat (any Codex Astra-line id, or fable) for this session only.

Codex and Grok seats name a model LINE; the card resolves each to the newest id visible here
(model_lines.py). A newer id in a known line is used automatically; an unknown line needs recon.
      --confirmed attests the second yes; without it the command refuses. Never carried to another session.

Exit 0 for build (a card with warnings is still a card); 64 on bad usage.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import model_lines as ml  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULTS = os.path.join(HERE, "..", "references", "routing-defaults.json")
FH = os.environ.get("FOREMAN_HOME") or os.path.join(os.path.expanduser("~"), ".foreman")
TODAY = dt.date.fromisoformat(os.environ["FOREMAN_TODAY"]) if os.environ.get("FOREMAN_TODAY") else dt.date.today()
RECON = os.path.join(FH, "recon", "models.json")
PREFS = os.path.join(FH, "session-prefs.md")


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(64)


# ---------------------------------------------------------------- availability
def parse_probe(text, consented):
    av = {"claude": dict(up=True, consent=True, proven=True, models={"opus", "fable", "sonnet", "haiku", "LEAD"}, note="session harness"),
          "lead": dict(up=True, consent=True, proven=True, models={"inline"}, note="")}
    codex_up = bool(re.search(r"^codex auth: .*[Ll]ogged in", text, re.M))
    codex_pre = bool(re.search(r"^codex billing: PRE-APPROVED", text, re.M)) or "codex" in consented
    av["codex"] = dict(up=codex_up, consent=codex_pre, proven=False, models=set(re.findall(r"^\s{2}([a-z0-9][\w.-]*): \"", text, re.M)),
                       note="signed in" if codex_up else ("not installed" if "codex: NOT installed" in text else "not signed in"))
    m = re.search(r"^grok access: (\S+)", text, re.M)
    gstate = m.group(1) if m else ("NOT-INSTALLED" if "grok: NOT installed" in text else "UNKNOWN")
    gl = re.search(r"^grok models \(live, this account\): (.*?) \(CLI default", text, re.M)
    grok_pre = bool(re.search(r"^grok billing: PRE-APPROVED", text, re.M)) or "grok" in consented
    av["grok"] = dict(up=gstate == "SIGNED-IN", consent=grok_pre, proven=False, models=set(gl.group(1).split()) if gl else set(),
                      note={"SIGNED-IN": "signed in",
                            "ENV-MISMATCH": "UNKNOWN from this shell — re-probe unsandboxed before routing around it"}.get(gstate, gstate.lower()))
    jev_in = bool(re.search(r"^jev: opted in", text, re.M))
    av["jev"] = dict(up=jev_in, consent=True, proven=False, models={"jev"}, note="opted in" if jev_in else "not opted in")
    return av


def apply_access(av, text):
    for prov, verdict in re.findall(r"^ACCESS (\w+): (\S+)", text, re.M):
        if prov not in av:
            continue
        if verdict in ("LIVE", "REACHABLE"):
            av[prov].update(up=True, proven=True)
        elif verdict != "SIGNED_IN":
            av[prov]["up"] = False
        av[prov]["note"] = f"access-check: {verdict}"


PREMIUM = {}
APPROVED = set()


def resolve(av, s):
    """Fill s['model'] for a line seat with the newest id visible in this account (None if none)."""
    if "line" in s and "model" not in s:
        s["model"] = ml.newest(s["provider"], s["line"], av.get(s["provider"], {}).get("models", set())) or None
    return s


def seat_key(s):
    return f"{s['provider']}:{s.get('line') or s['model']}"


def seat_state(av, s):
    """-> (usable, label). Fails CLOSED: a provider whose model list could not be read is not usable."""
    resolve(av, s)
    if s["model"] and (s.get("premium") or ml.is_premium(s["provider"], s["model"])) and s["model"] not in APPROVED:
        return False, "premium — needs the user's double approval this session"
    p = av.get(s["provider"])
    if not p or not p["up"]:
        return False, (p or {}).get("note", "absent")
    if s["provider"] in ("codex", "grok"):
        if not p["models"]:
            return False, "model list unparsed — do not dispatch off this card; re-run the probe"
        if not s["model"]:
            return False, f"no visible model in the {s.get('line')} line"
        if s["model"] not in p["models"]:
            return False, "not in this account's model list"
        if not p["consent"]:
            return False, "needs the user's consent (spends their plan)"
    if s["provider"] in ("codex", "grok", "jev"):
        return True, "proven live" if p["proven"] else "signed in, untested — run access-check before the first dispatch"
    return True, ""


def fmt(s):
    e = f" @ {s['effort']}" if s.get("effort") and s["effort"] not in ("n/a", "session") else ""
    sb = f", {s['sandbox']}" if s.get("sandbox") else ""
    ln = f" (newest {s['line']})" if s.get("line") else ""
    return f"{s['provider']}:{s.get('model') or '<none>'}{ln}{e}{sb}"


def plain(s):
    return s.get("plain", s.get("model") or "").replace("{model}", s.get("model") or s.get("line", ""))


# ---------------------------------------------------------------- memory
def load_recon():
    try:
        rows = json.load(open(RECON))
    except (OSError, ValueError):
        return []
    live = []
    for r in rows if isinstance(rows, list) else []:
        try:
            if dt.date.fromisoformat(r["expires"]) >= TODAY:
                live.append(r)
        except (KeyError, ValueError, TypeError):
            continue
    return live


def load_prefs():
    out = []
    if os.path.exists(PREFS):
        for line in open(PREFS, encoding="utf-8"):
            m = re.match(r"- (\d{4}-\d{2}-\d{2}) \| ([^|]+) \| ([^|]*) \| ([\w-]+) \| (.+)$", line.strip())
            if m:
                out.append(dict(date=m.group(1), session=m.group(2).strip(), project=m.group(3).strip(),
                                job=m.group(4), choice=m.group(5).strip()))
    return out


# ---------------------------------------------------------------- build
def build(probe_text, access_text, session, project, consented, show_probe, premium_cli):
    d = json.load(open(DEFAULTS))
    PREMIUM.update(d.get("premium_lines", {}))
    APPROVED.update(premium_cli)
    APPROVED.update(p["choice"] for p in load_prefs() if p["job"] == "premium" and session and p["session"] == session)
    av = parse_probe(probe_text, consented)
    if access_text:
        apply_access(av, access_text)
    recon = load_recon()
    jobs = {j["id"]: j for j in d["jobs"]}
    applied = []
    recon_lines, ignored = {}, []
    for r in recon:
        if r.get("verdict") != "use":
            continue
        pr = ml.parse(r["provider"], r["model"])
        if pr and pr[0] in ml.KNOWN_LINES.get(r["provider"], set()):
            # A known line already resolves to its newest release; a verdict naming one
            # release must never pin it (it would bring back a superseded model).
            ignored.append(f"{r['model']} (known line — its newest release is used automatically)")
            continue
        if pr and not pr[2]:
            recon_lines.setdefault(r["provider"], set()).add(pr[0])
        seat = {"provider": r["provider"], "effort": "lead judgment",
                "why": f"recon {r['date']}: {r.get('note', '')}", "plain": "{model} — newly evaluated line" + f" ({r['date']})"}
        if pr and not pr[2]:
            seat["line"] = pr[0]
        else:
            seat["model"] = r["model"]
        for jid in r.get("jobs", []):
            j = jobs.get(jid)
            if not j:
                continue
            if j["kind"] == "settled":
                j["default"] = [seat] + j["default"]
            else:
                j["options"] = [seat] + j["options"]
                j["judgment_prior"] = seat_key(seat)
            applied.append(f"{r['provider']}:{seat.get('line') or seat['model']} line → {jid}")
    evaluated = {p: set(v) for p, v in d["evaluated"].items() if not p.startswith("_")}
    for r in recon:  # a recon-evaluated release is the baseline for its line
        if r.get("verdict") == "use":
            evaluated.setdefault(r["provider"], set()).add(r["model"])
    recon_models = {(r["provider"], r["model"]) for r in recon}
    for j in d["jobs"]:
        for s in j.get("default", []) + j.get("fallbacks", []) + j.get("options", []):
            resolve(av, s)
    age = (TODAY - dt.date.fromisoformat(d["verified"])).days
    recon_today = any(r.get("date") == TODAY.isoformat() for r in recon)

    L = [f"# Routing card — {TODAY.isoformat()}", "",
         "**Precedence:** user constraints → live access and consent → context ceiling → this card's settled row "
         "→ close-call answer or judgment prior. model-matrix.md is evidence for recon and deviations, not a second menu.", ""]
    if age > d["stale_after_days"] and not recon_today:
        L.append(f"**STALE** — suggestions verified {d['verified']} ({age} days). Run ONE bounded recon pass (routing.md, Recon), "
                 "save verdicts with `recon-record`, then rebuild. No web access: keep these seats and say so in the ledger and final message.")
    elif age > d["stale_after_days"]:
        L.append(f"Suggestions verified {d['verified']}; **recon already done today — do not repeat it.** Existing seats stand where recon said nothing.")
    else:
        L.append(f"Suggestions verified {d['verified']} ({age} days ago). Fresh.")
    used_lines = {(s["provider"], s["line"]) for j in d["jobs"] for s in j.get("default", []) + j.get("fallbacks", []) + j.get("options", []) if "line" in s}
    new, succ, old = [], [], []
    for p in ("codex", "grok"):
        for mid, st, line, note in ml.classify(p, av[p]["models"], evaluated.get(p, ()), recon_lines.get(p, ())):
            if ((p, mid) in recon_models and st in ("new-line", "unrecognized")) or mid in d["never_request"]:
                continue
            if st in ("new-line", "unrecognized"):
                new.append(f"{p}:{mid}")
            elif st == "newest" and note and (p, line) in used_lines:
                succ.append(f"{p}:{mid} (newest {line})")
            elif st == "superseded":
                old.append(f"{p}:{mid}")
    L.append(f"**NEW MODEL LINES — recon required before routing to them:** {', '.join(new)}. Never route to an unevaluated line on a guess."
             if new else "No unevaluated model lines on this machine.")
    if succ:
        L.append(f"**Newer release in a known line — used automatically:** {', '.join(succ)}. Before its first real dispatch, ping it "
                 "once (`access-check.sh <provider> --consented --model <id>`); if the ping fails, use the next-newest id in that line and "
                 "ledger `line <line> resolved to <id> (newer than evaluated)` or the fallback reason.")
    if old:
        L.append(f"Superseded (older releases in a line that has a newer one) — never route to them: {', '.join(old)}.")
    if applied:
        L.append("Recon verdicts applied: " + "; ".join(applied))
    if ignored:
        L.append("Recon verdicts ignored: " + "; ".join(ignored))
    trials = [f"{r['model']} ({r['date']}: prove on one representative ticket vs the incumbent)" for r in recon if r.get("verdict") == "trial"]
    if trials:
        L.append("Candidates on trial: " + "; ".join(trials))

    L += ["", "| Provider | State |", "|---|---|"]
    for p in ("claude", "codex", "grok", "jev"):
        a = av[p]
        st = "UNAVAILABLE" if not a["up"] else ("needs consent" if not a["consent"] else ("proven live" if a["proven"] else "available, untested"))
        L.append(f"| {p} | {st} — {a['note']} |")

    L += ["", "## Settled — use the seat shown unless an allowed reason applies", "",
          "| Job | Use | Then | Evidence | Why |", "|---|---|---|---|---|"]
    consent_asks = []
    for j in d["jobs"]:
        if j["kind"] != "settled":
            continue
        first, pick = j["default"][0], None
        for s in j["default"] + j.get("fallbacks", []):
            if seat_state(av, s)[0]:
                pick = s
                break
        use = f"**{fmt(pick)}**" if pick else "**no seat available — park as NEEDS USER**"
        if pick is not None and pick is not first:
            why_not = seat_state(av, first)[1]
            use += f" *(default {fmt(first)}: {why_not})*"
            if "consent" in why_not:
                consent_asks.append((j, first))
        if pick is not None and pick.get("note"):
            use += f" — {pick['note']}"
        rest = [fmt(s) for s in j.get("fallbacks", []) if s is not pick and seat_state(av, s)[0]]
        extra = " ".join(x for x in (j.get("escalate", ""), j.get("no_agent_tool", "")) if x)
        L.append(f"| {j['label']} | {use} | {', '.join(rest) or '—'} | {j.get('evidence', '')} | {j['why']}{(' ' + extra) if extra else ''} |")

    prefs = load_prefs()
    L += ["", "## Close calls", ""]
    to_ask, offers = [], []
    for j in d["jobs"]:
        if j["kind"] != "close":
            continue
        opts = [s for s in j["options"] if seat_state(av, s)[0]]
        names = {s["model"] for s in opts} | {"judgment"}
        keys = {seat_key(s): s["model"] for s in opts}
        L.append(f"### {j['label']} (`{j['id']}`)")
        for s in j["options"]:
            ok, why = seat_state(av, s)
            L.append(f"- {fmt(s)} — {s['why']}" + ("" if ok else f" — **unavailable: {why}**"))
        prior = keys.get(j.get("judgment_prior")) or (opts[0]["model"] if opts else None)
        for p in prefs:  # an answer naming an older release in a line means that line's newest release today
            if p["job"] == j["id"]:
                for s in opts:
                    pp = ml.parse(s["provider"], p["choice"]) if "line" in s else None
                    if pp and pp[0] == s["line"] and not pp[2] and p["choice"] != s["model"]:
                        p["choice"] = f"{s['model']} (newest {s['line']}; answer named {p['choice']})"
                        p["mapped"] = s["model"]
        mine = [p for p in prefs if p["job"] == j["id"] and session and p["session"] == session]
        usable = {s["model"] for s in opts} | {"judgment"}
        usable |= {m for m in APPROVED if m == "fable" or m in av.get("codex", {}).get("models", set())}  # user-requested, double-approved
        if mine and mine[-1].get("mapped", mine[-1]["choice"]) not in usable:
            L.append(f"- Chosen this session: {mine[-1]['choice']} — **not usable right now** (absent, unconsented, superseded or unapproved); "
                     f"start from **{prior}** and tell the user, or park as NEEDS USER if no option is available.")
        elif mine:
            L.append(f"- **Chosen this session: {mine[-1]['choice']} — apply it; do not ask again.**")
        elif len(opts) >= 2:
            L.append(f"- Unattended, or told \"use your judgment\": start from **{prior}**; another listed option needs a `task-fit` "
                     "reason naming the strength that matters. Transport or wrapper overhead is not a reason here either.")
            older = [p for p in prefs if p["job"] == j["id"] and not is_premium_id(p["choice"]) and (not project or p["project"] in ("", project))
                     and (TODAY - dt.date.fromisoformat(p["date"])).days <= d["prefs_expire_days"] and p.get("mapped", p["choice"]) in names]
            if older:
                offers.append((j, older[-1]))
            else:
                to_ask.append((j, opts, prior))
        elif len(opts) == 1:
            L.append(f"- Only {fmt(opts[0])} is available — use it; no question.")
        else:
            L.append("- No option available — park as NEEDS USER.")
        L.append("")

    if to_ask or offers or consent_asks:
        L += ["## The one question — ask once, before the first affected dispatch; drop parts this run will not hit", ""]
        parts = []
        for j, opts, prior in to_ask:
            ordered = sorted(opts, key=lambda s: s["model"] != prior)
            parts.append(f"For {j['ask_topic']}: " + "; ".join(plain(s) for s in ordered)
                         + f". I'd suggest {plain(ordered[0]).split(' —')[0]}.")
        for j, p in offers:
            parts.append(f"Last time ({p['date']}) you chose {p['choice']} for {j['ask_topic']}; keep that?")
        for j, s in consent_asks:
            parts.append(f"May I use {s['provider'].capitalize()} (it spends your {s['provider'].capitalize()} plan) "
                         f"for {j['label'].split(':')[0].lower()}?")
        prem_note = ""
        if any(j["id"] == "hard-coding" for j, _, _ in to_ask):
            prem_note = (" (Premium models — Codex Astra, Claude Fable — are never picked automatically; they are used only if you "
                         "ask for one, and I'd then confirm once more, with the cost, before using it.)")
        L.append("> " + " ".join(parts) + " Or I can use my best judgment. I'll remember your answer for the rest of this session." + prem_note)
        L += ["", "Record each answer: `routing-card.py remember <job-id> <choice|judgment> --session <run-id>`. Unattended runs do not "
              "ask: use the judgment prior (or the settled fallback when consent is missing), ledger it, and report it in the final message.", ""]

    L += ["## Premium seats — double approval, this session only", ""]
    for key, why in PREMIUM.items():
        prov, line = key.split(":")
        ids = ml.ranked(prov, line, av.get(prov, {}).get("models", set())) if prov != "claude" else [line]
        appr = [m for m in ids if m in APPROVED]
        st = f"**approved this session: {', '.join(appr)}**" if appr else "not approved — never dispatch, never a fallback, never an option"
        L.append(f"- `{key}` (here: {', '.join(ids) or 'none visible'}) — {why}: {st}")
    L += ["", d.get("premium_rule", ""),
          "Ask: \"<model> is the premium tier (<cost comparison>). Use it for <job>?\" Then, after a yes, confirm once: "
          "\"To confirm: <model> for <job> this session, at roughly <cost>. Go ahead?\" Only after the second yes run "
          "`routing-card.py approve-premium <model> --session <run-id> --confirmed` and rebuild the card.", ""]
    L += ["## Never request", ""] + [f"- `{k}` — {v}" for k, v in d["never_request"].items()]
    L += ["", "## Allowed reasons to deviate (ledger the key verbatim)", ""]
    L += [f"- `{r.split(':')[0]}` — {r.split(':', 1)[1].strip()}" for r in d["allowed_deviation_reasons"]]
    L += ["", "Not reasons: " + "; ".join(f'"{x}"' for x in d["forbidden_reasons"]) + ". The quality bar never drops for price (First Law)."]
    card = "\n".join(L) + "\n"
    if show_probe:
        card += "\n## Probe output (ledger it once)\n\n```\n" + probe_text.strip() + "\n```\n"
    os.makedirs(FH, exist_ok=True)
    with open(os.path.join(FH, "routing-card.md"), "w", encoding="utf-8") as f:
        f.write(card)
    return card


# ---------------------------------------------------------------- commands
def opt(args, name, default=None):
    if name in args:
        i = args.index(name)
        if i + 1 >= len(args):
            die(f"{name} needs a value")
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default


def is_premium_id(model):
    return ml.is_premium("codex", model) or ml.is_premium("claude", model)


def main(a):
    args = a[1:]
    cmd = args.pop(0) if args and args[0] in ("build", "remember", "recon-record", "approve-premium") else "build"
    d = json.load(open(DEFAULTS))
    if cmd == "remember":
        session = opt(args, "--session")
        project = opt(args, "--project", os.getcwd())
        if len(args) != 2 or not session:
            die("usage: routing-card.py remember <job-id> <choice|judgment> --session ID [--project DIR]")
        job, choice = args
        jobs = {j["id"]: j for j in d["jobs"] if j["kind"] == "close"}
        if job not in jobs:
            die(f"BLOCKED: '{job}' is not a close-call job (close calls: {', '.join(sorted(jobs))})")
        opts = jobs[job]["options"]
        valid = {s["model"] for s in opts if "model" in s} | {"judgment"} | {r["model"] for r in load_recon() if job in r.get("jobs", [])}
        recon_lines = [{"provider": r["provider"], "line": ml.parse(r["provider"], r["model"])[0]} for r in load_recon()
                       if job in r.get("jobs", []) and r.get("verdict") == "use" and ml.parse(r["provider"], r["model"])]
        line_ok = any("line" in s and (ml.parse(s["provider"], choice) or ("",))[0] == s["line"]
                      and not ml.parse(s["provider"], choice)[2] for s in opts + recon_lines)
        approved = any(p["job"] == "premium" and p["session"] == session and p["choice"] == choice for p in load_prefs())
        if choice not in valid and not line_ok and not (approved and is_premium_id(choice)):
            lines = [f"newest {s['provider']} {s['line']} id" for s in opts if "line" in s]
            die(f"BLOCKED: '{choice}' is not an option for {job} (options: {', '.join(sorted(valid) + lines)})")
        if is_premium_id(choice) and not any(p["job"] == "premium" and p["session"] == session and p["choice"] == choice for p in load_prefs()):
            die(f"BLOCKED: {choice} is a premium seat — record the user's double approval first (approve-premium {choice} --session {session} --confirmed)")
        os.makedirs(FH, exist_ok=True)
        with open(PREFS, "a", encoding="utf-8") as f:
            f.write(f"- {TODAY.isoformat()} | {session} | {project} | {job} | {choice}\n")
        print(f"remembered for session {session}: {job} -> {choice} (offered back in later sessions for "
              f"{d['prefs_expire_days']} days, never applied silently)")
        return
    if cmd == "approve-premium":
        session = opt(args, "--session")
        confirmed = "--confirmed" in args
        args = [x for x in args if x != "--confirmed"]
        if len(args) != 1 or not session:
            die("usage: routing-card.py approve-premium <model> --session ID --confirmed")
        model = args[0]
        if not is_premium_id(model):
            die(f"BLOCKED: '{model}' is not a premium seat (premium lines: {', '.join(d.get('premium_lines', {}))})")
        if not confirmed:
            die("BLOCKED: premium seats need the user's second, confirming yes — ask the confirmation question, then pass --confirmed")
        os.makedirs(FH, exist_ok=True)
        with open(PREFS, "a", encoding="utf-8") as f:
            f.write(f"- {TODAY.isoformat()} | {session} | {os.getcwd()} | premium | {model}\n")
        print(f"premium seat {model} approved (twice) for session {session} only")
        return
    if cmd == "recon-record":
        if len(args) < 6:
            die("usage: routing-card.py recon-record <provider> <model> <use|trial|ignore> <job-ids,comma|-> <valid-days> <note...>")
        prov, model, verdict, jobs_s, days = args[:5]
        note = " ".join(args[5:])
        if verdict not in ("use", "trial", "ignore"):
            die("BLOCKED: verdict must be use, trial or ignore")
        jids = [] if jobs_s == "-" else jobs_s.split(",")
        bad = [x for x in jids if x not in {j["id"] for j in d["jobs"]}]
        if bad:
            die(f"BLOCKED: unknown job ids {bad}")
        if not days.isdigit() or not 1 <= int(days) <= 90:
            die("BLOCKED: valid-days must be 1-90")
        try:
            rows = json.load(open(RECON))
        except (OSError, ValueError):
            rows = []
        rows = [r for r in rows if not (r.get("provider") == prov and r.get("model") == model)]
        rows.append(dict(provider=prov, model=model, verdict=verdict, jobs=jids, date=TODAY.isoformat(),
                         expires=(TODAY + dt.timedelta(days=int(days))).isoformat(), note=note))
        os.makedirs(os.path.dirname(RECON), exist_ok=True)
        with open(RECON, "w") as f:
            json.dump(rows, f, indent=1)
        print(f"recon verdict saved: {prov}:{model} = {verdict} for {jids or 'no jobs'} until {rows[-1]['expires']}")
        return
    probe_file = opt(args, "--probe-output")
    access_file = opt(args, "--access")
    session = opt(args, "--session", "")
    project = opt(args, "--project", os.getcwd())
    consented = set(filter(None, (opt(args, "--consented", "") or "").split(",")))
    premium_cli = set(filter(None, (opt(args, "--premium-approved", "") or "").split(",")))
    if args:
        die(__doc__)
    if probe_file:
        probe_text, show = open(probe_file, encoding="utf-8", errors="replace").read(), False
    else:
        probe_text, show = subprocess.run(["sh", os.path.join(HERE, "probe.sh")], capture_output=True, text=True).stdout, True
    access_text = open(access_file, encoding="utf-8").read() if access_file else ""
    print(build(probe_text, access_text, session, project, consented, show, premium_cli), end="")


if __name__ == "__main__":
    main(sys.argv)
