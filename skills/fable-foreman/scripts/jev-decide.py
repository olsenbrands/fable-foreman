#!/usr/bin/env python3
"""fable-foreman — fixed-contract launcher for TypeSafe Jev structured decisions.

Jev is NOT a worker seat. It is a structured-decision primitive: given a JSON
"state" it answers typed questions (noul = yes/no probability, choice = one of
up to 255 options with a full distribution, score = a 2-10 level rubric) in one
cheap call. The foreman uses it to replace LLM calls on narrow, high-volume
triage decisions (references/jev.md). Its answers are advisory signals the lead
weighs — never acceptance, never a sole security gate.

Usage:
  jev-decide.py check                        # access verdict (free key check + one tiny decision)
  jev-decide.py run <request.json> <artifact.json>
      request.json = {"state": {...}, "questions": {"name": {"type": ..., ...}}}
                     ("model" optional; defaults to the provider's jev-latest alias)

Opt-in (user-set, per machine, never created by the agent):
  $FOREMAN_HOME/jev-enabled (default ~/.foreman/jev-enabled) or FOREMAN_JEV=1.
  The flag file may carry lines:
    provider: openrouter | typesafe       (default openrouter)
    keychain-service: <macOS keychain service name holding the key>
    privacy: metadata | snippets          (default metadata — see jev.md)
    model: <id>                           (override; e.g. a newer typesafe/jev-X.Y on OpenRouter)

Key resolution (first hit wins; values are never printed):
  TYPESAFE_API_KEY  -> TypeSafe direct endpoint
  OPENROUTER_API_KEY -> OpenRouter alpha decisions endpoint
  keychain-service from the flag file -> provider from the flag file

Exit codes: 0 ok | 3 disabled (no opt-in) | 4 no key | 5 key rejected |
            6 transport failure/timeout/rate limit | 64 invalid request
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ENDPOINTS = {
    # OpenRouter accepts only exact versions: "typesafe/jev-latest" and
    # "typesafe/jev-1.13.0" both return 400 "does not exist" (OBSERVED
    # 2026-09-23). The alias works on TypeSafe's own endpoint only.
    "openrouter": ("https://openrouter.ai/api/alpha/decisions", "typesafe/jev-1.13"),
    "typesafe": ("https://api.typesafe.ai/v1/systemone", "jev-latest"),
}
OPENROUTER_KEY_URL = "https://openrouter.ai/api/v1/key"
# Documented limits (docs.typesafe.ai/models, checked 2026-09-23): 32K state
# tokens, 64K request tokens. Tokens are not counted here; bytes/4 is a
# conservative stand-in so an oversized request is refused before any spend.
MAX_STATE_BYTES = 32_000 * 4
MAX_REQUEST_BYTES = 64_000 * 4
MAX_CHOICES = 255
QUESTION_TYPES = {"noul", "choice", "score"}


def foreman_home():
    return os.environ.get("FOREMAN_HOME") or os.path.join(os.path.expanduser("~"), ".foreman")


def read_flag():
    """Return (enabled, settings) from the opt-in flag file / env."""
    path = os.path.join(foreman_home(), "jev-enabled")
    settings = {}
    enabled = os.environ.get("FOREMAN_JEV") == "1"
    if os.path.isfile(path):
        enabled = True
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    if ":" in line and not line.lstrip().startswith("#"):
                        k, v = line.split(":", 1)
                        settings[k.strip().lower()] = v.strip()
        except OSError:
            pass
    return enabled, settings


def resolve_key(settings):
    """Return (key, provider, source-label). Never returns the key in a label."""
    if os.environ.get("TYPESAFE_API_KEY"):
        return os.environ["TYPESAFE_API_KEY"].strip(), "typesafe", "env:TYPESAFE_API_KEY"
    if os.environ.get("OPENROUTER_API_KEY"):
        return os.environ["OPENROUTER_API_KEY"].strip(), "openrouter", "env:OPENROUTER_API_KEY"
    svc = settings.get("keychain-service")
    if svc and sys.platform == "darwin":
        try:
            r = subprocess.run(["security", "find-generic-password", "-s", svc, "-w"],
                               capture_output=True, text=True, timeout=10)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip(), settings.get("provider", "openrouter"), f"keychain:{svc}"
        except (OSError, subprocess.SubprocessError):
            pass
    return None, settings.get("provider", "openrouter"), "none"


def endpoint_for(provider, settings=None):
    url, model = ENDPOINTS.get(provider, ENDPOINTS["openrouter"])
    model = (settings or {}).get("model") or model
    return os.environ.get("FOREMAN_JEV_ENDPOINT", url), os.environ.get("FOREMAN_JEV_MODEL", model)


def validate(req):
    if not isinstance(req, dict):
        return "request must be a JSON object"
    state, qs = req.get("state"), req.get("questions")
    if not isinstance(state, dict) or not state:
        return "request.state must be a non-empty object"
    if not isinstance(qs, dict) or not qs:
        return "request.questions must be a non-empty object"
    for name, q in qs.items():
        if not isinstance(q, dict) or q.get("type") not in QUESTION_TYPES:
            return f"question '{name}' must have type noul|choice|score"
        if not isinstance(q.get("instructions"), str) or not q["instructions"].strip():
            return f"question '{name}' needs non-empty instructions"
        if q["type"] == "choice":
            crit = q.get("criteria")
            if not isinstance(crit, dict) or len(crit) < 2:
                return f"choice '{name}' needs a criteria object with >= 2 options"
            if len(crit) > MAX_CHOICES:
                return f"choice '{name}' has {len(crit)} options (max {MAX_CHOICES})"
    sb = len(json.dumps(state).encode())
    rb = len(json.dumps(req).encode())
    if sb > MAX_STATE_BYTES:
        return f"state is {sb} bytes (> {MAX_STATE_BYTES}, ~32K-token limit) — shrink or batch"
    if rb > MAX_REQUEST_BYTES:
        return f"request is {rb} bytes (> {MAX_REQUEST_BYTES}, ~64K-token limit) — shrink or batch"
    return None


def post(url, key, body, timeout):
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8", "replace"), time.time() - t
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t
    except Exception as e:  # timeout, DNS, TLS, refused
        return None, f"{type(e).__name__}: {e}", time.time() - t


def redact(text, key):
    """Never echo credential material from a provider's error body."""
    if key:
        text = text.replace(key, "<redacted>")
    return re.sub(r"(sk-[A-Za-z0-9_-]{4})[A-Za-z0-9_-]{8,}", r"\1…<redacted>", text)


def classify(status, text=""):
    if status == 400 and "does not exist" in text:
        return "MODEL_NOT_FOUND — set 'model: <exact id>' in the jev-enabled flag file (OpenRouter needs an exact version such as typesafe/jev-1.13)", 6
    return _classify(status)


def _classify(status):
    if status == 200:
        return "REACHABLE", 0
    if status in (401, 403):
        return "KEY_REJECTED", 5
    if status == 402:
        return "NO_CREDIT", 6
    if status == 429:
        return "RATE_LIMITED", 6
    if status is None:
        return "TRANSPORT_FAILED", 6
    return f"HTTP_{status}", 6


def gate():
    enabled, settings = read_flag()
    if not enabled:
        print("jev access: DISABLED — no user opt-in ($FOREMAN_HOME/jev-enabled or FOREMAN_JEV=1). "
              "The skill runs identically without Jev.")
        sys.exit(3)
    key, provider, source = resolve_key(settings)
    if not key:
        print(f"jev access: NO_KEY — opted in, but no key found (env TYPESAFE_API_KEY / OPENROUTER_API_KEY, "
              f"or keychain-service in the flag file). provider={provider}")
        sys.exit(4)
    return key, provider, source, settings


def cmd_check():
    key, provider, source, settings = gate()
    url, model = endpoint_for(provider, settings)
    timeout = float(os.environ.get("FOREMAN_JEV_TIMEOUT", "15"))
    print(f"jev key: present ({source}; value withheld) provider={provider}")
    # Free check first where the provider has one: OpenRouter's key endpoint
    # costs nothing and distinguishes a revoked key from a network problem.
    if provider == "openrouter" and "FOREMAN_JEV_ENDPOINT" not in os.environ:
        r = urllib.request.Request(OPENROUTER_KEY_URL, headers={"Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                print(f"jev key check: OpenRouter accepted the key (HTTP {resp.status}, free call)")
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                print(f"jev access: KEY_REJECTED — OpenRouter refused the key (HTTP {e.code}, free call). "
                      "Rotate or re-store the key; nothing was spent.")
                sys.exit(5)
            print(f"jev key check: HTTP {e.code} (continuing to a live decision)")
        except Exception as e:
            print(f"jev key check: {type(e).__name__} (continuing to a live decision)")
    body = json.dumps({"model": model,
                       "state": {"value": "ping"},
                       "questions": {"q": {"type": "noul", "instructions": "Is the value exactly the word ping?"}}}).encode()
    status, text, lat = post(url, key, body, timeout)
    verdict, code = classify(status, text)
    detail = ""
    if status == 200:
        try:
            d = json.loads(text)
            ans = ((d.get("answers") or {}).get("q") or {}).get("noul") if isinstance(d, dict) else None
            if not isinstance(ans, (int, float)):
                verdict, code = "MALFORMED_RESPONSE", 6
                detail = f" detail={redact(text[:160], key)!r}"
            else:
                detail = f" answer={ans} usage={d.get('usage')}"
        except ValueError:
            verdict, code = "MALFORMED_RESPONSE", 6
    else:
        detail = f" detail={redact(text[:160], key)!r}"
    print(f"jev access: {verdict} — live decision via {url} model={model} latency={lat:.2f}s{detail}")
    sys.exit(code)


def cmd_run(req_path, out_path):
    if not out_path.endswith(".json") or os.path.islink(out_path) or (os.path.exists(out_path) and os.path.getsize(out_path) > 0):
        print(f"BLOCKED: artifact must be a fresh .json path, not a symlink or non-empty file: {out_path}", file=sys.stderr)
        sys.exit(64)
    try:
        with open(req_path, encoding="utf-8") as f:
            req = json.load(f)
    except (OSError, ValueError) as e:
        print(f"BLOCKED: cannot read request {req_path}: {e}", file=sys.stderr)
        sys.exit(64)
    err = validate(req)
    if err:
        print(f"BLOCKED: {err}", file=sys.stderr)
        sys.exit(64)
    key, provider, source, settings = gate()
    url, model = endpoint_for(provider, settings)
    req.setdefault("model", model)
    body = json.dumps(req).encode()
    status, text, lat = post(url, key, body, float(os.environ.get("FOREMAN_JEV_TIMEOUT", "10")))
    verdict, code = classify(status, text)
    text = redact(text, key)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"jev access: {verdict}")
    print(f"endpoint: {url}  model requested: {req['model']}  key: {source} (value withheld)")
    print(f"latency: {lat:.2f}s  request bytes: {len(body)}  artifact: {out_path}")
    if status == 200:
        try:
            d = json.loads(text)
            if not isinstance(d, dict) or not isinstance(d.get("answers"), dict) or not d["answers"]:
                raise ValueError("no answers object")
            print(f"usage: {d.get('usage')}")
            print(f"model reported: {d.get('model', 'unavailable')}")
            for name, a in (d.get("answers") or {}).items():
                if isinstance(a, dict) and "noul" in a:
                    print(f"answer {name}: noul={a['noul']}")
                elif isinstance(a, dict) and isinstance(a.get("probabilities"), dict):
                    top = sorted(a["probabilities"].items(), key=lambda kv: -kv[1])[:3]
                    print(f"answer {name}: top={top}")
                else:
                    print(f"answer {name}: {json.dumps(a)[:200]}")
        except ValueError:
            print("jev access: MALFORMED_RESPONSE — artifact kept for diagnosis")
            code = 6
    else:
        print(f"detail: {text[:200]!r}")  # already redacted above
    print("reminder: Jev answers are advisory signals for the lead — never acceptance, never a sole gate (jev.md)")
    sys.exit(code)


def main(argv):
    if len(argv) >= 2 and argv[1] == "check":
        cmd_check()
    elif len(argv) == 4 and argv[1] == "run":
        cmd_run(argv[2], argv[3])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(64)


if __name__ == "__main__":
    main(sys.argv)
