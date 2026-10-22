#!/usr/bin/env python3
"""fable-foreman — find the newest model in each line, from the provider's own live list.

Seats are named by LINE, never by a pinned id, so a new release in a line the skill
already knows is picked up automatically and a superseded one is never chosen:

  codex  gpt-<version>-<line>   lines: sol (workhorse), luna (fast), astra (frontier, PREMIUM), terra
  grok   grok-<version>         line "base"; suffixed ids (grok-4.7-build-fast) are variants, never defaults
  claude harness aliases (opus, sonnet, haiku, fable) already track the newest model; fable is PREMIUM

Versions compare numerically (6.1 > 6 > 5.6; 6.10 > 6.9). An id that matches no known
line is a NEW LINE: it needs a bounded recon pass before any routing.

Usage:
  model_lines.py resolve <codex|grok> <line> [--models id,id,...]
      Without --models, codex reads ${CODEX_HOME:-~/.codex}/models_cache.json (visible entries only)
      and grok reads the probe's live list from `sh probe.sh`. Prints the newest id or exits 3.
  model_lines.py classify <codex|grok> --models id,id,... [--evaluated id,id,...]
      One line per id: newest / superseded / variant / new-line, with the line it belongs to.
"""
import json
import os
import re
import subprocess
import sys

CODEX_RE = re.compile(r"^gpt-(\d+(?:\.\d+)*)-([a-z]+)$")
GROK_RE = re.compile(r"^grok-(\d+(?:\.\d+)*)(-[a-z0-9-]+)?$")
KNOWN_LINES = {"codex": {"sol", "luna", "astra", "terra"}, "grok": {"base"}, "claude": {"opus", "sonnet", "haiku", "fable"}}
PREMIUM_LINES = {"codex": {"astra"}, "claude": {"fable"}}


def version_key(v):
    return tuple(int(x) for x in v.split("."))


def parse(provider, model):
    """-> (line, version-tuple, is_variant) or None when the id has no recognizable shape."""
    if provider == "codex":
        m = CODEX_RE.match(model or "")
        return (m.group(2), version_key(m.group(1)), False) if m else None
    if provider == "grok":
        m = GROK_RE.match(model or "")
        return ("base", version_key(m.group(1)), bool(m.group(2))) if m else None
    if provider == "claude":
        alias = (model or "").split("-")[1] if (model or "").startswith("claude-") else model
        return (alias, (), False) if alias in KNOWN_LINES["claude"] else None
    return None


def newest(provider, line, models):
    """Highest-version non-variant id in `line` among `models`, or None."""
    best = None
    for mid in models:
        p = parse(provider, mid)
        if p and p[0] == line and not p[2] and (best is None or p[1] > best[0]):
            best = (p[1], mid)
    return best[1] if best else None


def ranked(provider, line, models):
    """All non-variant ids in `line`, newest first (the fallback order when a ping refuses one)."""
    rows = [(parse(provider, m)[1], m) for m in models
            if parse(provider, m) and parse(provider, m)[0] == line and not parse(provider, m)[2]]
    return [m for _, m in sorted(rows, reverse=True)]


def is_premium(provider, model):
    m = (model or "").lower()
    if provider == "codex":
        return bool(re.search(r"(^|-)astra($|-)", m))
    if provider == "claude":
        return "fable" in m
    return False


def classify(provider, models, evaluated=(), extra_lines=()):
    """-> list of (id, status, line, note). status: newest | superseded | variant | new-line | unrecognized.
    extra_lines: lines a recon pass has already evaluated (treated as known)."""
    known = KNOWN_LINES.get(provider, set()) | set(extra_lines)
    out = []
    for mid in sorted(models):
        p = parse(provider, mid)
        if not p:
            out.append((mid, "unrecognized", "", "no known id shape — not a seat; recon before any use"))
            continue
        line, _, variant = p
        if line not in known:
            out.append((mid, "new-line", line, "a model line this skill has never evaluated — recon first"))
        elif variant:
            out.append((mid, "variant", line, "priced/behaving differently from its base model — only on the user's request"))
        elif newest(provider, line, models) == mid:
            base = [parse(provider, e)[1] for e in evaluated if parse(provider, e) and parse(provider, e)[0] == line]
            newer = not base or p[1] > max(base)
            note = "newer than the evaluated release — same line's successor: ping once, then use" if newer and mid not in evaluated else ""
            out.append((mid, "newest", line, note))
        else:
            out.append((mid, "superseded", line, f"older than {newest(provider, line, models)} — never route to it"))
    return out


def codex_catalog():
    mc = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "models_cache.json")
    try:
        rows = json.load(open(mc)).get("models", [])
    except (OSError, ValueError, AttributeError):
        return []
    return [m.get("slug") for m in rows if isinstance(m, dict) and m.get("slug") and m.get("visibility") in (None, "list")]


def grok_live():
    here = os.path.dirname(os.path.abspath(__file__))
    text = subprocess.run(["sh", os.path.join(here, "probe.sh")], capture_output=True, text=True).stdout
    m = re.search(r"^grok models \(live, this account\): (.*?) \(CLI default", text, re.M)
    return m.group(1).split() if m else []


def main(argv):
    args = argv[1:]
    def opt(name):
        if name in args:
            i = args.index(name)
            v = args[i + 1] if i + 1 < len(args) else ""
            del args[i:i + 2]
            return [x for x in v.split(",") if x]
        return None
    models, evaluated = opt("--models"), opt("--evaluated") or []
    if len(args) >= 2 and args[0] in ("resolve", "classify") and args[1] in ("codex", "grok"):
        cmd, prov = args[0], args[1]
        if models is None:
            models = codex_catalog() if prov == "codex" else grok_live()
        if cmd == "resolve" and len(args) == 3:
            got = newest(prov, args[2], models)
            if not got:
                print(f"no visible {prov} model in line '{args[2]}'", file=sys.stderr)
                sys.exit(3)
            print(got + ("  (PREMIUM — double approval required)" if is_premium(prov, got) else ""))
            return
        if cmd == "classify" and len(args) == 2:
            for mid, st, line, note in classify(prov, models, evaluated):
                print(f"{prov}:{mid}\t{st}\t{line}\t{note}")
            return
    print(__doc__, file=sys.stderr)
    sys.exit(64)


if __name__ == "__main__":
    main(sys.argv)
