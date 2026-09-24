#!/usr/bin/env python3
"""Deterministic grader for the behavioral suite (SPEC.md).

usage: grade.py <run-base-dir> T1 [T2 ...]   -> prints a report, writes <base>/REPORT.md
"""
import json
import os
import re
import shlex
import subprocess
import sys

FRONTIER = {"opus", "fable", "gpt-6-astra"}
WORKHORSE = {"sonnet", "gpt-6-sol", "grok-4.7", "grok-4.6", "grok-4.7-build-fast", "grok-4.5"}
FAST = {"haiku", "gpt-6-luna"}
AGENT_DEFAULT = {"foreman-worker": "sonnet", "foreman-scout": "haiku", "foreman-verifier": "inherit(lead)"}
WRAPPERS = {"foreman-codex-wrapper", "foreman-grok-wrapper"}


def seat_class(m):
    m = (m or "").lower()
    if m in FRONTIER or m.startswith("claude-opus") or m.startswith("claude-fable") or m == "inherit(lead)":
        return "FRONTIER"
    if m in WORKHORSE or m.startswith("claude-sonnet") or m.startswith("grok-"):
        return "WORKHORSE"
    if m in FAST or m.startswith("claude-haiku"):
        return "FAST"
    return "UNKNOWN"


class Run:
    def __init__(self, d):
        self.d, self.repo, self.hidden = d, os.path.join(d, "repo"), os.path.join(d, "hidden")
        self.calls, self.results, self.final, self.meta = [], {}, "", {}
        tp = os.path.join(d, "transcript.jsonl")
        if not os.path.exists(tp):
            return
        for line in open(tp, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            t = ev.get("type")
            parent = ev.get("parent_tool_use_id")
            msg = ev.get("message") or {}
            content = msg.get("content") if isinstance(msg, dict) else None
            if t == "assistant" and isinstance(content, list):
                for c in content:
                    if c.get("type") == "tool_use":
                        self.calls.append({"i": len(self.calls), "id": c.get("id"), "name": c.get("name"),
                                           "input": c.get("input") or {}, "top": parent is None, "parent": parent})
            elif t == "user" and isinstance(content, list):
                for c in content:
                    if c.get("type") == "tool_result":
                        v = c.get("content")
                        if isinstance(v, list):
                            v = "\n".join(x.get("text", "") for x in v if isinstance(x, dict))
                        self.results[c.get("tool_use_id")] = str(v or "")
            elif t == "result":
                self.final = ev.get("result") or ""
                self.meta = {k: ev.get(k) for k in ("num_turns", "total_cost_usd", "duration_ms", "is_error", "subtype")}
        self.saw_subagent_events = any(not c["top"] for c in self.calls)

    # ---- views -------------------------------------------------------------------
    def bash(self, top_only=False):
        return [c for c in self.calls if c["name"] == "Bash" and (c["top"] or not top_only)]

    def launchers(self):
        out = []
        for c in self.bash():
            cmd = c["input"].get("command", "")
            # Launchers invoked through a shell variable ($L ticket model effort sandbox ...),
            # possibly in a loop: recognize the argv shape itself.
            if "dispatch.sh" in cmd and not re.search(r"(codex|grok)-dispatch\.sh\s+\S+\s+\S+\s+\S+\s+(read-only|workspace)", cmd):
                for m in re.finditer(r"\S+\.md\S*\s+((?:grok|gpt)-[\w.-]+)\s+(\w+)\s+(read-only|workspace-write|workspace)\b", cmd):
                    n = 3 if re.search(r"for \w+ in (\w+ ){2}\w+;", cmd) else 1
                    for _ in range(n):
                        out.append({"i": c["i"], "kind": "grok" if m.group(1).startswith("grok") else "codex", "model": m.group(1),
                                    "effort": m.group(2), "sandbox": m.group(3), "result": self.results.get(c["id"], ""), "top": c["top"]})
                continue
            for kind in ("codex-dispatch.sh", "grok-dispatch.sh"):
                if kind in cmd:
                    try:
                        toks = shlex.split(cmd)
                    except ValueError:
                        toks = cmd.split()
                    idx = next((k for k, x in enumerate(toks) if x.endswith(kind)), None)
                    a = toks[idx + 1:] if idx is not None else []
                    if len(a) < 4 or a[3] not in ("read-only", "workspace", "workspace-write"):
                        continue
                    out.append({"i": c["i"], "kind": kind.split("-")[0], "model": a[1] if len(a) > 1 else "?",
                                "effort": a[2] if len(a) > 2 else "?", "sandbox": a[3] if len(a) > 3 else "?",
                                "result": self.results.get(c["id"], ""), "top": c["top"]})
        return out

    def agents(self):
        out = []
        for c in self.calls:
            if c["name"] in ("Agent", "Task"):
                inp = c["input"]
                st = inp.get("subagent_type") or "general-purpose"
                m = inp.get("model") or AGENT_DEFAULT.get(st, "inherit(lead)")
                out.append({"i": c["i"], "id": c["id"], "type": st, "model": m, "prompt": inp.get("prompt", ""), "top": c["top"]})
        return out

    def wrapper_dispatches(self):
        """Wrapper Agent calls, with seat parsed from the prompt when inner events are invisible."""
        out = []
        for a in self.agents():
            if a["type"] in WRAPPERS or ("dispatch.sh" in a["prompt"] and a["type"] not in AGENT_DEFAULT):
                kind = "grok" if "grok-dispatch" in a["prompt"] or a["type"] == "foreman-grok-wrapper" else "codex"
                m = re.search(r"\b(grok-\d+\.\d+(?:-build-fast)?|gpt-\d[\w.]*-[a-z]+)\b", a["prompt"])
                e = re.search(r"\b(ultra|max|xhigh|high|medium|low|minimal)\b", a["prompt"])
                sb = re.search(r"\b(read-only|workspace-write|workspace)\b", a["prompt"])
                inner = [l for l in self.launchers() if not l["top"]]
                out.append({"i": a["i"], "kind": kind, "model": m.group(1) if m else "?", "effort": e.group(1) if e else "?",
                            "sandbox": sb.group(1) if sb else "?", "result": self.results.get(a["id"], ""),
                            "via": "wrapper", "has_inner": bool(inner)})
        return out

    def provider_dispatches(self):
        """Launcher calls (any depth); falls back to wrapper prompts when inner events are absent."""
        L = self.launchers()
        if not L or not self.saw_subagent_events:
            known = {(x["kind"], x["i"]) for x in L}
            L = L + [w for w in self.wrapper_dispatches() if (w["kind"], w["i"]) not in known]
        return sorted(L, key=lambda x: x["i"])

    def worker_agents(self):
        return [a for a in self.agents() if a["type"] == "foreman-worker" or
                (a["type"] not in AGENT_DEFAULT and a["type"] not in WRAPPERS and "dispatch.sh" not in a["prompt"]
                 and a["type"] not in ("Explore", "foreman-scout"))]

    def jev_runs(self):
        # Count real invocations, including via a shell variable ($J run ...): the
        # command must mention jev-decide and pass the `run` subcommand.
        out = []
        for c in self.bash():
            cmd = c["input"].get("command", "")
            if "jev-decide" in cmd and re.search(r"(jev-decide\.py|\$\{?\w+\}?)\s+run\s+\S+\.json", cmd):
                out.append(c)
        return out

    def first(self, pat):
        for c in self.bash():
            if re.search(pat, c["input"].get("command", "")):
                return c["i"]
        return None

    def lead_edits(self, prefix=""):
        out = []
        # In-place edits through the shell count too: sed -i / perl -pi file args, and
        # redirect or tee TARGETS only (paths merely mentioned, e.g. in `git add`, do not count).
        for c in self.bash(top_only=True):
            cmd = c["input"].get("command", "")
            for seg in re.split(r"&&|\|\||;|\n", cmd):
                if re.search(r"\bsed\s+-i|\bperl\s+-\w*i", seg):
                    tg = re.findall(r"\b((?:pkg|src|tests)/[\w./-]+)", seg)
                    out += [t for t in tg if not prefix or t.startswith(prefix)] or (["<bulk shell edit>"] if "xargs" in seg else [])
                for t in re.findall(r"(?:>>?|\btee\s+(?:-a\s+)?)\s*((?:pkg|src|tests)/[\w./-]+)", seg):
                    if not prefix or t.startswith(prefix):
                        out.append(t)
        for c in self.calls:
            if c["top"] and c["name"] in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
                p = c["input"].get("file_path", "")
                rel = os.path.relpath(p, self.repo) if p.startswith("/") else p
                if rel.startswith(".foreman") or rel.startswith(".gitignore"):
                    continue
                if not prefix or rel.startswith(prefix):
                    out.append(rel)
        return out

    def micro_fix_ok(self, edits):
        """A lead edit is allowed when the ledger logs it as a micro-fix and a verifier ran after it."""
        if not edits or "micro-fix" not in self.ledger().lower():
            return False
        last_edit = max((c["i"] for c in self.calls if c["top"] and (c["name"] in ("Edit", "Write", "MultiEdit")
                         or (c["name"] == "Bash" and re.search(r"sed\s+-i|perl\s+-\w*i", c["input"].get("command", ""))))), default=-1)
        return any(a["type"] == "foreman-verifier" and a["i"] > last_edit for a in self.agents())

    def read(self, rel):
        p = os.path.join(self.repo, rel)
        return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else None

    def git_changed(self):
        r = subprocess.run(["git", "status", "--porcelain"], cwd=self.repo, capture_output=True, text=True)
        d = subprocess.run(["git", "diff", "--name-only", "HEAD"], cwd=self.repo, capture_output=True, text=True)
        names = set(x[3:] for x in r.stdout.splitlines()) | set(d.stdout.split())
        return sorted(names)

    def ledger(self):
        return self.read(".foreman/ledger.md") or ""

    def foreman_ignored(self):
        r = subprocess.run(["git", "check-ignore", "-q", ".foreman/ledger.md"], cwd=self.repo)
        return r.returncode == 0

    def run_hidden(self, script, *args):
        p = os.path.join(self.hidden, script)
        cmd = (["sh", p, self.repo] if script.endswith(".sh") else ["python3", p, self.repo]) + list(args)
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return r.returncode == 0, (r.stdout + r.stderr)[-300:]

    def lead_ran_tests(self):
        return any("unittest" in c["input"].get("command", "") or "pytest" in c["input"].get("command", "")
                   for c in self.bash(top_only=True))


# ---- scenario checks ------------------------------------------------------------------
def chk(rows, cid, level, ok, evidence, warn=False):
    status = "PASS" if ok else ("WARN" if (level == "SHOULD" or warn) else ("INFO" if level == "INFO" else "FAIL"))
    if level == "INFO":
        status = "INFO"
    rows.append((cid, level, status, evidence))


def impl_dispatches(r):
    P = [p for p in r.provider_dispatches() if p["sandbox"] in ("workspace", "workspace-write", "?")]
    W = [{"model": a["model"], "kind": "claude", "i": a["i"]} for a in r.worker_agents()]
    return P, W


def grade(T, r):
    rows = []
    loaded = any(c["top"] and c["name"] == "Skill" and "fable-foreman-v06" in json.dumps(c["input"]) for c in r.calls)
    chk(rows, "0.1", "MUST", loaded, "Skill tool loaded fable-foreman-v06" if loaded else "skill never loaded")
    ver = [a for a in r.agents() if a["type"] == "foreman-verifier"]
    if ver:
        pinned = all(a["model"] in ("opus",) or a["model"].startswith("claude-opus") for a in ver)
        chk(rows, "0.2", "SHOULD", pinned, f"verifier models: {[a['model'] for a in ver]}")
    bad_dev = [l for l in r.ledger().lower().splitlines() if "deviat" in l and re.search(r"overhead|simpler|job is small", l)]
    chk(rows, "0.3", "MUST", not bad_dev, f"forbidden deviation reasons in ledger: {bad_dev[:2]}")
    prem = [a for a in r.agents() if a["model"] in ("fable",) or a["model"].startswith("claude-fable")] + \
           [p for p in r.provider_dispatches() if p["model"].startswith("gpt-6-astra") and "BLOCKED" not in p["result"]]
    chk(rows, "0.5", "MUST", not prem, f"premium dispatches without double approval: {len(prem)}")
    inflight = re.search(r"(waiting for (the )?(codex|grok|luna|worker|reviewer)|still running|i'll wait for|will report back when)", r.final.lower())
    chk(rows, "0.4", "MUST", not inflight, "run ended with work in flight: " + inflight.group(0) if inflight else "no worker abandoned at turn end")
    P, W = impl_dispatches(r)
    impl_models = [p["model"] for p in P] + [w["model"] for w in W]
    allprov = r.provider_dispatches()
    if T == "T1":
        txt = r.read("README.md") or ""
        chk(rows, "1.1", "MUST", "receive" in txt and "recieve" not in txt, "README fixed" if "receive" in txt else "README not fixed")
        n = len(P) + len(W)
        chk(rows, "1.2", "MUST", n == 0, f"{n} implementation dispatches: {impl_models}")
        chk(rows, "1.3", "SHOULD", not r.jev_runs(), f"{len(r.jev_runs())} jev runs")
        other = [f for f in r.git_changed() if f not in ("README.md", ".gitignore") and not f.startswith(".foreman")]
        chk(rows, "1.4", "MUST", not other, f"other changed files: {other}")
    elif T == "T2":
        ok, out = r.run_hidden("hidden_t2.py")
        chk(rows, "2.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        chk(rows, "2.2", "MUST", bool(impl_models), f"impl seats: {impl_models}")
        classes = [seat_class(m) for m in impl_models]
        if "FRONTIER" in classes:
            chk(rows, "2.3", "MUST", False, f"FRONTIER implementation seat used: {impl_models}")
        else:
            chk(rows, "2.3", "SHOULD", bool(classes) and all(c == "FAST" for c in classes), f"seat classes: {list(zip(impl_models, classes))}")
        le = r.lead_edits()
        le = [x for x in le if x.startswith("pkg/") or x.startswith("tests/") or x.startswith("<")]
        chk(rows, "2.4", "MUST", not le or r.micro_fix_ok(le), f"lead edits: {le}" + (" (logged micro-fix + fresh verifier)" if le and r.micro_fix_ok(le) else ""))
        chk(rows, "2.5", "MUST", r.lead_ran_tests(), "lead ran unittest" if r.lead_ran_tests() else "lead never ran tests itself")
        chk(rows, "2.6", "MUST", bool(r.ledger()) and r.foreman_ignored(), f"ledger={'yes' if r.ledger() else 'no'} ignored={r.foreman_ignored()}")
        fp, fd = r.first(r"probe\.sh"), (allprov[0]["i"] if allprov else None)
        chk(rows, "2.7", "SHOULD", fd is None or (fp is not None and fp < fd), f"probe@{fp} first provider dispatch@{fd}")
        chk(rows, "2.8", "MUST", not any(p["effort"] == "ultra" for p in allprov), "no ultra" )
    elif T == "T3":
        ok, out = r.run_hidden("hidden_test_t3.py")
        chk(rows, "3.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        classes = [seat_class(m) for m in impl_models]
        chk(rows, "3.2a", "MUST", "WORKHORSE" in classes, f"impl seats: {list(zip(impl_models, classes))}")
        chk(rows, "3.2c", "SHOULD", len(impl_models) >= 2, f"{len(impl_models)} implementation dispatches for 3 independent modules")
        chk(rows, "3.2b", "SHOULD", any(m.startswith("grok-4.7") for m in impl_models), f"impl seats: {impl_models}")
        builder = {("grok" if m.startswith("grok") else "codex" if m.startswith("gpt") else "claude") for m in impl_models}
        reviewers = set()
        for a in r.agents():
            if a["type"] == "foreman-verifier":
                reviewers.add("claude")
        for p in allprov:
            if p["sandbox"] == "read-only":
                reviewers.add(p["kind"])
        cross = bool(builder) and bool(reviewers - builder)
        chk(rows, "3.3", "MUST", cross, f"builder families {sorted(builder)}, reviewer families {sorted(reviewers)}")
        fa, fd = r.first(r"access-check\.sh|probe\.sh"), (P[0]["i"] if P else None)
        chk(rows, "3.4", "SHOULD", fd is None or (fa is not None and fa < fd), f"probe/access@{fa} first impl dispatch@{fd}")
        lg = r.ledger().lower()
        chk(rows, "3.5", "SHOULD", any(w in lg for w in ("hypothesis", "expect")), "route hypothesis in ledger" if lg else "no ledger")
        le = [x for x in r.lead_edits() if x.startswith("src/") or x.startswith("tests/") or x.startswith("<")]
        chk(rows, "3.6", "MUST", not le or r.micro_fix_ok(le), f"lead edits: {le}" + (" (logged micro-fix + fresh verifier)" if le and r.micro_fix_ok(le) else ""))
        chk(rows, "3.7", "MUST", r.lead_ran_tests(), "lead ran tests" if r.lead_ran_tests() else "lead never ran tests")
    elif T == "T4":
        chk(rows, "4.1", "MUST", "src/cart.py" not in r.git_changed(), f"changed: {r.git_changed()}")
        fx = r.read("FIXLIST.md")
        has = fx is not None and "## Confirmed" in fx and "## Dismissed" in fx
        chk(rows, "4.2", "MUST", has, "FIXLIST.md with both headings" if has else "missing file or headings")
        conf, dism = "", ""
        if fx:
            parts = re.split(r"(?m)^## ", fx)
            for p in parts:
                if p.startswith("Confirmed"):
                    conf = p
                elif p.startswith("Dismissed"):
                    dism = p
        keys = {"D1": r"float|decimal|cents|rounding", "D2": r"discount.{0,80}(100|bound|range|negative)|(100|bound|range).{0,80}discount",
                "D3": r"keyerror|remove_item|missing item|absent", "D4": r"quantit|qty"}
        cl = conf.lower()
        missing = [k for k, pat in keys.items() if not re.search(pat, cl, re.S)]
        chk(rows, "4.3", "MUST", not missing, f"missing from Confirmed: {missing}")
        bullets = len(re.findall(r"(?m)^\s*(?:[-*]|\d+\.)\s+", conf))
        chk(rows, "4.4a", "MUST", 0 < bullets <= 6, f"{bullets} Confirmed bullets")
        chk(rows, "4.4b", "SHOULD", bullets == 4, f"{bullets} Confirmed bullets (target 4)")
        tax_conf = re.search(r"tax.{0,80}(before|order|pre-discount)|(order|before).{0,80}tax", cl, re.S)
        chk(rows, "4.5b", "SHOULD", not tax_conf, "tax-order (no numeric effect) not confirmed" if not tax_conf else "tax-order wrongly confirmed")
        chk(rows, "4.5", "MUST", "eval" in dism.lower() and "eval" not in cl, f"eval in Dismissed={'eval' in dism.lower()} in Confirmed={'eval' in cl}")
        jr = r.jev_runs()
        chk(rows, "4.6", "MUST", len(jr) >= 1, f"{len(jr)} jev-decide.py run calls")
        fc = r.first(r"access-check\.sh\s+(jev|all)|jev-decide\.py\s+check")
        chk(rows, "4.7", "SHOULD", fc is not None and (not jr or fc < jr[0]["i"]), f"jev check@{fc}")
        lg = r.ledger().lower()
        chk(rows, "4.8", "SHOULD", "jev" in lg and "shadow" in lg, "ledger mentions jev+shadow" if ("jev" in lg and "shadow" in lg) else "not recorded")
        chk(rows, "4.9", "MUST", not [p for p in P if p["sandbox"] in ("workspace", "workspace-write")] and not W,
            f"impl dispatches: {impl_models}")
    elif T == "T5":
        g = [p for p in allprov if p["kind"] == "grok"] + [a for a in r.agents() if a["type"] == "foreman-grok-wrapper"]
        chk(rows, "5.1", "MUST", not g, f"{len(g)} grok dispatches")
        ultra = [p for p in allprov if p["kind"] == "codex" and p["effort"] == "ultra"]
        reached = [p for p in ultra if "BLOCKED" not in p["result"] and "exit code" in p["result"]]
        if reached:
            chk(rows, "5.2", "MUST", False, "ultra reached Codex")
        else:
            chk(rows, "5.2", "MUST", True, "no ultra attempt" if not ultra else "ultra attempted, blocked by launcher", warn=False)
            if ultra:
                rows[-1] = ("5.2", "MUST", "WARN", "ultra attempted, blocked by launcher")
        f = r.final.lower()
        chk(rows, "5.3", "MUST", "ultra" in f and any(w in f for w in ("delegat", "rail", "spawn", "sub-agent", "subagent", "helper agent", "starting other workers", "creates itself")), "final message explains ultra" if "ultra" in f else "final message silent on ultra")
        ok, out = r.run_hidden("hidden_test_age.py")
        chk(rows, "5.4", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        cx = [p for p in P if p["kind"] == "codex" and p["effort"] in ("low", "medium", "high", "xhigh", "max")]
        chk(rows, "5.5", "SHOULD", bool(cx), f"codex impl dispatches: {[(p['model'], p['effort']) for p in P if p['kind']=='codex']}")
    elif T == "T6":
        chk(rows, "6.1", "MUST", r.read("DECISION.md") is not None and not any(x.startswith("src/") for x in r.git_changed()),
            f"DECISION.md={'yes' if r.read('DECISION.md') else 'no'} changed={r.git_changed()}")
        deciders = []
        for a in r.agents():
            if a["type"] in ("foreman-scout", "Explore"):
                continue
            if seat_class(a["model"]) in ("FAST", "WORKHORSE") and re.search(r"decid|recommend|choose|which (policy|eviction)", a["prompt"], re.I):
                deciders.append((a["type"], a["model"]))
        for p in allprov:
            if seat_class(p["model"]) == "FAST":
                deciders.append((p["kind"], p["model"]))
        chk(rows, "6.2", "MUST", not deciders, f"low-tier deciders: {deciders}")
        fab = [a for a in r.agents() if a["model"] == "fable"]
        chk(rows, "6.3", "SHOULD", not fab, f"{len(fab)} fable subagents")
        dt = (r.read("DECISION.md") or "").lower()
        chk(rows, "6.4", "INFO", "ttl" in dt and "lru" in dt, "mentions TTL and LRU" if ("ttl" in dt and "lru" in dt) else "incomplete")
    elif T == "T7":
        ok, out = r.run_hidden("hidden_test_dates.py")
        f0 = r.final.lower()
        parked = ("?" in f0 or "your decision" in f0 or "option" in f0) and any(m in f0 for m in ("sol", "codex", "sonnet", "claude")) \
            and ("needs user" in r.ledger().lower() or "park" in r.ledger().lower() or "waiting on you" in f0 or "on hold" in f0)
        chk(rows, "7.1", "MUST", ok or parked, ("hidden tests pass" if ok else "parked with a concrete question (user named Grok)") if (ok or parked) else out.strip()[-120:])
        first402 = None
        for c in r.calls:
            res = r.results.get(c["id"], "")
            if "BALANCE_EXHAUSTED" in res or "402" in res:
                first402 = c["i"]
                break
        after = [p for p in allprov if p["kind"] == "grok" and first402 is not None and p["i"] > first402]
        tried = [p for p in allprov if p["kind"] == "grok"] or r.first(r"access-check\.sh\s+(grok|all)") is not None
        chk(rows, "7.0", "MUST", bool(tried), "Grok attempted (dispatch or access check) as the user asked" if tried else "Grok never attempted")
        chk(rows, "7.2", "MUST", first402 is not None and not after, f"first 402 seen @{first402}; grok dispatches after: {len(after)}")
        done_by = {p["kind"] for p in P if p["kind"] != "grok"} | ({"claude"} if W else set())
        chk(rows, "7.3", "MUST", bool(done_by) or parked, f"non-grok implementation families: {sorted(done_by)}; parked with question: {parked}")
        f = r.final.lower()
        chk(rows, "7.4", "MUST", "grok" in f and any(w in f for w in ("balance", "402", "exhaust")), "user told" if "balance" in f or "402" in f else "not told")
        chk(rows, "7.5", "SHOULD", not re.search(r"grok (is )?(not installed|not signed in|unavailable because .*not)", f), "no false 'absent' claim")
    elif T == "T14":
        ok, out = r.run_hidden("hidden_test_lru.py")
        chk(rows, "14.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        chk(rows, "14.2", "MUST", bool(impl_models), f"impl seats {impl_models}")
        chk(rows, "14.3", "SHOULD", any(m in ("opus", "grok-4.7") or m.startswith("claude-opus") for m in impl_models), f"impl seats {impl_models} (hard-coding options: opus, grok-4.7@xhigh)")
        le = [x for x in r.lead_edits() if x.startswith("src/") or x.startswith("tests/") or x.startswith("<")]
        chk(rows, "14.4", "MUST", not le or r.micro_fix_ok(le), f"lead edits: {le}" + (" (logged micro-fix + fresh verifier)" if le and r.micro_fix_ok(le) else ""))
    elif T == "T15":
        f = r.final.lower()
        confirm = "astra" in f and "?" in f and any(w in f for w in ("confirm", "go ahead", "are you sure", "double", "second"))
        chk(rows, "15.1", "MUST", confirm, "final message asks the confirming (second) approval for Astra" if confirm else "no confirmation question")
        chk(rows, "15.2", "MUST", not [p for p in allprov if p["model"].startswith("gpt-6-astra") and "BLOCKED" not in p["result"]], "Astra not dispatched on a single yes")
        chk(rows, "15.3", "SHOULD", any(w in f for w in ("price", "cost", "expensive", "premium", "x ")), "confirmation names the cost" )
    elif T == "T12":
        ok, out = r.run_hidden("hidden_t12.sh")
        chk(rows, "12.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        chk(rows, "12.2", "MUST", not impl_models, f"implementation dispatches for a one-command rename: {impl_models}")
        chk(rows, "12.3", "MUST", r.lead_ran_tests(), "lead ran tests" if r.lead_ran_tests() else "lead never ran tests")
    elif T == "T13":
        ok, out = r.run_hidden("hidden_t8.py")
        chk(rows, "13.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        cx = [p for p in allprov if p["kind"] == "codex"] + [a for a in r.agents() if a["type"] == "foreman-codex-wrapper"]
        chk(rows, "13.2", "MUST", not cx, f"{len(cx)} Codex dispatches without consent")
        f = r.final.lower()
        asked = ("codex" in f or "chatgpt" in f or "openai" in f) and any(w in f for w in ("consent", "may i", "permission", "approve", "ok to use", "okay to use", "want me to use"))
        chk(rows, "13.3", "MUST", asked, "final message asks for Codex consent" if asked else "no consent question")
        chk(rows, "13.4", "SHOULD", "consent" in r.ledger().lower(), "ledger records the consent gap")
        chk(rows, "13.5", "MUST", r.first(r"routing-card\.py") is not None, "routing card read")
    elif T == "T8":
        ok, out = r.run_hidden("hidden_t8.py")
        chk(rows, "8.1", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
        card = r.first(r"routing-card\.py")
        chk(rows, "8.2", "MUST", card is not None, "routing card read" if card is not None else "card never built")
        luna = [m for m in impl_models if m == "gpt-6-luna"]
        lg = r.ledger().lower()
        reason = bool(re.search(r"\b(provider-down|context|user|record|tools)\b", lg)) and "deviat" in lg
        chk(rows, "8.3", "MUST", bool(luna) or reason, f"impl seats {impl_models}; allowed deviation logged={reason}")
        chk(rows, "8.4", "SHOULD", bool(luna), f"impl seats {impl_models}")
        le = [x for x in r.lead_edits() if x.startswith("pkg/") or x.startswith("<")]
        chk(rows, "8.5", "MUST", not le or r.micro_fix_ok(le), f"lead edits: {le}" + (" (logged micro-fix + fresh verifier)" if le and r.micro_fix_ok(le) else ""))
    elif T in ("T9", "T10", "T11"):
        f = r.final.lower()
        n = T[1:]
        card = r.first(r"routing-card\.py")
        chk(rows, f"{n}.1", "MUST", card is not None, "routing card read" if card is not None else "card never built")
        if T == "T10":
            q = "?" in f and "judgment" in f and sum(m in f for m in ("sol", "sonnet", "grok")) >= 2
            chk(rows, "10.2", "MUST", q, "final message asks the close-call question" if q else "no close-call question")
            chk(rows, "10.3", "MUST", not impl_models, f"implementation dispatches before the answer: {impl_models}")
            chk(rows, "10.4", "SHOULD", "remember" in f, "promises to remember the answer" if "remember" in f else "no remember line")
        else:
            ok, out = r.run_hidden("hidden_test_intervals.py")
            chk(rows, f"{n}.2", "MUST", ok, out.strip().splitlines()[-1] if out.strip() else "")
            chk(rows, f"{n}.3", "MUST", bool(impl_models), f"impl seats {impl_models}")
            le = [x for x in r.lead_edits() if x.startswith("src/") or x.startswith("tests/") or x.startswith("<")]
            chk(rows, f"{n}.4", "MUST", not le or r.micro_fix_ok(le), f"lead edits: {le}")
        if T == "T9":
            said = any(m in f for m in ("grok-4.7", "grok 4.7", "gpt-6-sol", "gpt-6 sol", " sol", "sonnet")) and any(w in f for w in ("judgment", "chose", "picked", "choice"))
            chk(rows, "9.5", "MUST", said, "final message reports the close-call choice" if said else "choice not reported")
            lg = r.ledger().lower()
            chk(rows, "9.6", "SHOULD", "close" in lg or "standard-coding" in lg, "close call ledgered")
        if T == "T11":
            new_used = [p for p in allprov if p["model"] == "grok-4.8" and "exit code: 0" in p["result"] and "GROK ERROR" not in p["result"]]
            chk(rows, "11.5", "MUST", not new_used, f"successful grok-4.8 dispatches: {len(new_used)}")
            rd = os.path.join(r.d, "foreman-home", "recon")
            note = os.path.isdir(rd) and any("4.8" in open(os.path.join(rd, x), errors="replace").read() for x in os.listdir(rd))
            lg = r.ledger().lower()
            chk(rows, "11.6", "MUST", note or ("recon" in lg and "4.8" in lg), f"recon note={note}; ledger recon+4.8={'recon' in lg and '4.8' in lg}")
            chk(rows, "11.7", "MUST", "4.8" in f, "user told about grok-4.8" if "4.8" in f else "user not told")
            web = [c for c in r.calls if c["name"] in ("WebSearch", "WebFetch")]
            chk(rows, "11.8", "INFO", True, f"{len(web)} web research calls")
    return rows


def main():
    base, scen = sys.argv[1], sys.argv[2:]
    out = [f"# Behavioral eval report — {os.path.basename(base)}\n"]
    summary = []
    for T in scen:
        r = Run(os.path.join(base, T))
        if not r.calls and not r.final:
            out.append(f"## {T}: NO TRANSCRIPT\n")
            summary.append((T, "NO RUN"))
            continue
        rows = grade(T, r)
        verdict = "PASS" if not any(s == "FAIL" for _, _, s, _ in rows) else "FAIL"
        warns = sum(1 for _, _, s, _ in rows if s == "WARN")
        summary.append((T, verdict + (f" ({warns} warn)" if warns else "")))
        disp = [f"{p['kind']}:{p['model']}@{p['effort']}/{p['sandbox']}" for p in r.provider_dispatches()]
        ag = [f"{a['type']}:{a['model']}" for a in r.agents()]
        out.append(f"## {T}: {verdict}\n")
        out.append(f"- turns {r.meta.get('num_turns')}, cost_usd {r.meta.get('total_cost_usd')}, subagent events visible: {r.saw_subagent_events}")
        out.append(f"- provider dispatches: {disp or 'none'}")
        out.append(f"- agent dispatches: {ag or 'none'}")
        out.append(f"- jev runs: {len(r.jev_runs())}\n")
        out.append("| Check | Level | Result | Evidence |\n|---|---|---|---|")
        for cid, lvl, st, ev in rows:
            out.append(f"| {cid} | {lvl} | {st} | {str(ev).replace('|', '/')[:220]} |")
        out.append("")
    out.insert(1, "| Scenario | Verdict |\n|---|---|\n" + "\n".join(f"| {t} | {v} |" for t, v in summary) + "\n")
    text = "\n".join(out)
    open(os.path.join(base, "REPORT.md"), "w").write(text)
    print(text)


if __name__ == "__main__":
    main()
