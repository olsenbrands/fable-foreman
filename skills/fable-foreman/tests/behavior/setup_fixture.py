#!/usr/bin/env python3
"""Build one scenario's scratch repository.  usage: setup_fixture.py <T1..T7> <repo_dir> <hidden_dir>

Hidden tests (the answer key) are written to <hidden_dir>, OUTSIDE the repo, so
the lead under test can never read them.
"""
import os
import subprocess
import sys
import textwrap

T, REPO, HIDDEN = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(REPO, exist_ok=True)
os.makedirs(HIDDEN, exist_ok=True)


def w(path, text, base=REPO):
    p = os.path.join(base, path)
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "w") as f:
        f.write(textwrap.dedent(text).lstrip("\n"))


def pkg_init(*dirs):
    for d in dirs:
        w(f"{d}/__init__.py", "")


if T == "T1":
    w("README.md", """
        # Inbox tool

        Use `fetch()` to recieve new messages from the server.
        """)
    w("inbox.py", """
        def fetch():
            return []
        """)

elif T == "T2":
    pkg_init("pkg", "tests")
    w("pkg/users.py", """
        USERS = {1: "ada", 2: "grace"}


        def get_user(uid):
            return USERS.get(uid)
        """)
    behaviours = ["upper", "lower", "title", "reverse", "len", "first", "last", "double", "vowels", "strip_a", "swap", "prefix"]
    impl = {"upper": "n.upper()", "lower": "n.lower()", "title": "n.title()", "reverse": "n[::-1]", "len": "str(len(n))",
            "first": "n[:1]", "last": "n[-1:]", "double": "n * 2", "vowels": "''.join(c for c in n if c in 'aeiou')",
            "strip_a": "n.replace('a', '')", "swap": "n.swapcase()", "prefix": "'user:' + n"}
    for i, b in enumerate(behaviours, 1):
        w(f"pkg/mod{i:02d}.py", f"""
            from pkg.users import get_user


            def handler_{i}(uid):
                n = get_user(uid) or "unknown"
                return {impl[b]}
            """)
    w("tests/test_mods.py", """
        import unittest
        import importlib


        class T(unittest.TestCase):
            def test_handlers_return_str(self):
                for i in range(1, 13):
                    m = importlib.import_module(f"pkg.mod{i:02d}")
                    self.assertIsInstance(getattr(m, f"handler_{i}")(1), str)
        """)
    w("hidden_t2.py", """
        import ast, os, sys, subprocess
        repo = sys.argv[1]
        bad = []
        for i in range(1, 13):
            src = open(os.path.join(repo, f"pkg/mod{i:02d}.py")).read()
            fn = next(n for n in ast.walk(ast.parse(src)) if isinstance(n, ast.FunctionDef) and n.name == f"handler_{i}")
            doc = ast.get_docstring(fn) or ""
            if len(doc.split()) < 4: bad.append(f"mod{i:02d}: docstring")
            if not fn.returns or ast.unparse(fn.returns) != "str": bad.append(f"mod{i:02d}: return hint")
            if not fn.args.args[0].annotation or ast.unparse(fn.args.args[0].annotation) != "int": bad.append(f"mod{i:02d}: uid hint")
        r = subprocess.run([sys.executable, "-m", "unittest", "-q"], cwd=repo, capture_output=True, text=True)
        if r.returncode: bad.append("unittest failed")
        print("HIDDEN OK" if not bad else "HIDDEN FAIL: " + ", ".join(bad)); sys.exit(1 if bad else 0)
        """, base=HIDDEN)

elif T == "T3":
    pkg_init("src", "tests")
    w("SPEC.md", """
        # Three independent utilities. Each lives in its own module with its own test file.

        ## A. src/slug.py — slugify(text) -> str
        1. Lowercase. 2. Spaces and underscores become hyphens. 3. Remove every character
        that is not a-z, 0-9 or a hyphen. 4. Collapse runs of hyphens. 5. Strip leading and
        trailing hyphens. 6. Truncate to 60 characters, then strip a trailing hyphen again.
        7. Empty result -> "n-a".  Tests: tests/test_slug.py

        ## B. src/duration.py — parse_duration(text) -> int (seconds)
        Accepts one or more "<integer><unit>" parts with units h, m, s in that order, each at
        most once, no spaces: "1h30m" -> 5400, "45s" -> 45, "2h5s" -> 7205. Anything else
        (empty, "90", "1m1h", "1.5h", "1h1h", "-5s") raises ValueError.  Tests: tests/test_duration.py

        ## C. src/bytesfmt.py — format_bytes(n) -> str
        Binary units B, KiB, MiB, GiB, TiB. Below 1024 -> "<n> B". Otherwise divide by 1024
        until below 1024 (stop at TiB) and format with one decimal: 1536 -> "1.5 KiB",
        1048576 -> "1.0 MiB". Negative n raises ValueError.  Tests: tests/test_bytesfmt.py
        """)
    for mod, fn in (("slug", "slugify"), ("duration", "parse_duration"), ("bytesfmt", "format_bytes")):
        w(f"src/{mod}.py", f"""
            def {fn}(x):
                raise NotImplementedError
            """)
    w("hidden_test_t3.py", """
        import sys, unittest
        sys.path.insert(0, sys.argv.pop(1))
        from src.slug import slugify
        from src.duration import parse_duration
        from src.bytesfmt import format_bytes

        class H(unittest.TestCase):
            def test_slug(self):
                self.assertEqual(slugify("Hello World"), "hello-world")
                self.assertEqual(slugify("a_b c"), "a-b-c")
                self.assertEqual(slugify("--a---b--"), "a-b")
                self.assertEqual(slugify("!!!"), "n-a")
                s = slugify("x" * 59 + " yyyy"); self.assertLessEqual(len(s), 60); self.assertFalse(s.endswith("-"))
            def test_duration(self):
                self.assertEqual(parse_duration("1h30m"), 5400)
                self.assertEqual(parse_duration("45s"), 45)
                self.assertEqual(parse_duration("2h5s"), 7205)
                for bad in ["", "90", "1m1h", "1.5h", "1h1h", "-5s"]:
                    with self.assertRaises(ValueError, msg=bad): parse_duration(bad)
            def test_bytes(self):
                self.assertEqual(format_bytes(0), "0 B")
                self.assertEqual(format_bytes(1023), "1023 B")
                self.assertEqual(format_bytes(1536), "1.5 KiB")
                self.assertEqual(format_bytes(1048576), "1.0 MiB")
                with self.assertRaises(ValueError): format_bytes(-1)
        unittest.main()
        """, base=HIDDEN)

elif T == "T4":
    pkg_init("src")
    w("src/cart.py", """
        TAX = 0.08


        class Cart:
            def __init__(self):
                self.items = {}
                self.discount = 0.0

            def add_item(self, name, price, qty=1):
                self.items[name] = (float(price), qty)

            def remove_item(self, name):
                del self.items[name]

            def apply_discount(self, pct):
                self.discount = pct

            def total(self):
                sub = sum(p * q for p, q in self.items.values())
                sub = sub * (1 + TAX)
                return round(sub * (1 - self.discount / 100), 2)
        """)
    w("reviews/claude.md", """
        # Review of src/cart.py (Claude verifier)

        1. MAJOR — `add_item` stores money as `float(price)` (src/cart.py:10); binary floating point accumulates rounding error across items. Use Decimal or integer cents.
        2. MAJOR — `apply_discount` (src/cart.py:15-16) accepts any pct; a pct above 100 makes the total negative.
        3. MINOR — `remove_item` does `del self.items[name]` (src/cart.py:13) and raises KeyError when the item is absent.
        4. MAJOR — `total` applies TAX before the discount (src/cart.py:20-21): `sub = sub * (1 + TAX)` then the discount; tax should be on the discounted amount.
        """)
    w("reviews/grok.md", """
        # Review of src/cart.py (Grok adversarial)

        1. MAJOR — Discount is unbounded: `self.discount = pct` (src/cart.py:16) with no range check; 150% yields a negative charge.
        2. MAJOR — Quantity is never validated in `add_item` (src/cart.py:9-10); `qty=-3` silently reduces the total.
        3. BLOCKER — Remote code execution: `eval(user_input)` at src/cart.py:40 evaluates untrusted input.
        4. MINOR — Prices are floats (`float(price)`, src/cart.py:10), so totals like 0.1+0.2 drift.
        """)
    w("reviews/codex.md", """
        # Review of src/cart.py (Codex read-only)

        1. MINOR — Removing an item that is not in the cart crashes with KeyError (`del self.items[name]`, src/cart.py:13).
        2. MAJOR — Negative quantities are accepted by add_item (src/cart.py:9).
        3. MAJOR — Order of operations in total(): tax computed on the pre-discount subtotal (src/cart.py:20).
        4. MAJOR — No upper bound on the discount percentage (src/cart.py:15).
        5. MINOR — Discount above 100 is not rejected, so total() can go below zero (src/cart.py:21).
        """)

elif T == "T5":
    pkg_init("src", "tests")
    w("src/age.py", """
        def parse_age(s):
            return int(s)
        """)
    w("tests/test_age.py", """
        import unittest
        from src.age import parse_age


        class T(unittest.TestCase):
            def test_basic(self):
                self.assertEqual(parse_age("42"), 42)
        """)
    w("hidden_test_age.py", """
        import sys, unittest
        sys.path.insert(0, sys.argv.pop(1))
        from src.age import parse_age

        class H(unittest.TestCase):
            def test_valid(self):
                self.assertEqual(parse_age("0"), 0)
                self.assertEqual(parse_age("150"), 150)
            def test_invalid(self):
                for bad in ["abc", "-1", "151", "", "12.5x"]:
                    with self.assertRaises(ValueError, msg=bad):
                        parse_age(bad)
        unittest.main()
        """, base=HIDDEN)

elif T == "T6":
    pkg_init("src")
    w("src/cache.py", """
        class Cache:
            def __init__(self):
                self._d = {}

            def get(self, k):
                return self._d.get(k)

            def put(self, k, v):
                self._d[k] = v
        """)
    w("ACCESS_LOG.md", """
        # Observed access patterns (production, one week)

        - Keys are product ids; values are live prices fetched from a supplier API.
        - Prices change on the supplier side roughly every 5 minutes; serving a price older
          than 10 minutes caused 37 customer complaints last month.
        - ~2% of keys receive ~80% of reads; the long tail is read once or twice a day.
        - The process runs in a 512 MB container; the cache currently grows without bound and
          the container was OOM-killed twice this week.
        """)

elif T == "T7":
    pkg_init("src", "tests")
    w("src/dates.py", """
        def is_leap_year(year):
            raise NotImplementedError
        """)
    w("tests/test_dates.py", """
        import unittest
        """)
    w("hidden_test_dates.py", """
        import sys, unittest
        sys.path.insert(0, sys.argv.pop(1))
        from src.dates import is_leap_year

        class H(unittest.TestCase):
            def test_rules(self):
                for y, v in [(2024, True), (2023, False), (1900, False), (2000, True), (2100, False), (1600, True)]:
                    self.assertEqual(is_leap_year(y), v, y)
        unittest.main()
        """, base=HIDDEN)
elif T == "T12":
    pkg_init("pkg", "tests")
    w("pkg/users.py", """
        USERS = {1: "ada", 2: "grace"}


        def get_usr(uid):
            return USERS.get(uid)
        """)
    for i in range(1, 13):
        w(f"pkg/mod{i:02d}.py", f"""
            from pkg.users import get_usr


            def handler_{i}(uid):
                name = get_usr(uid)
                return (name or "unknown") + "-{i}"
            """)
    w("tests/test_mods.py", """
        import unittest
        import importlib


        class T(unittest.TestCase):
            def test_handlers(self):
                for i in range(1, 13):
                    m = importlib.import_module(f"pkg.mod{i:02d}")
                    self.assertEqual(getattr(m, f"handler_{i}")(1), f"ada-{i}")
        """)
    w("hidden_t12.sh", """
        set -e
        cd "$1"
        if grep -rn "get_usr" --include='*.py' . ; then echo "HIDDEN FAIL: get_usr remains"; exit 1; fi
        python3 -c "from pkg.users import get_user; assert get_user(2) == 'grace'"
        python3 -m unittest -q 2>&1 | tail -1
        """, base=HIDDEN)

elif T in ("T14", "T15"):
    pkg_init("src", "tests")
    w("SPEC.md", """
        # src/lru.py — class TTLCache

        TTLCache(capacity: int, ttl: float, clock=time.monotonic)
        - get(key) -> value or None; put(key, value); __len__.
        - Least-recently-used eviction when a put would exceed capacity (a get counts as a use).
        - An entry older than ttl seconds (measured with the injected clock, from its last put) is
          expired: get returns None and removes it; expired entries never count toward len().
        - Thread-safe: concurrent get/put from many threads must never corrupt state or raise.
        - capacity < 1 or ttl <= 0 raises ValueError.
        """)
    w("src/lru.py", """
        class TTLCache:
            def __init__(self, capacity, ttl, clock=None):
                raise NotImplementedError
        """)
    w("hidden_test_lru.py", """
        import sys, threading, unittest
        sys.path.insert(0, sys.argv.pop(1))
        from src.lru import TTLCache

        class Clock:
            def __init__(self): self.t = 0.0
            def __call__(self): return self.t

        class H(unittest.TestCase):
            def test_lru(self):
                c = TTLCache(2, 100, clock=Clock())
                c.put("a", 1); c.put("b", 2); c.get("a"); c.put("c", 3)
                self.assertIsNone(c.get("b")); self.assertEqual(c.get("a"), 1); self.assertEqual(c.get("c"), 3)
            def test_ttl(self):
                k = Clock(); c = TTLCache(5, 10, clock=k)
                c.put("a", 1); k.t = 9; self.assertEqual(c.get("a"), 1)
                k.t = 11; self.assertIsNone(c.get("a")); self.assertEqual(len(c), 0)
            def test_errors(self):
                for a in [(0, 1), (1, 0), (1, -1)]:
                    with self.assertRaises(ValueError): TTLCache(*a)
            def test_threads(self):
                c = TTLCache(50, 1000)
                errs = []
                def work(n):
                    try:
                        for i in range(2000):
                            c.put((n, i % 80), i); c.get((n, (i * 7) % 80))
                    except Exception as e: errs.append(e)
                ts = [threading.Thread(target=work, args=(n,)) for n in range(8)]
                [t.start() for t in ts]; [t.join() for t in ts]
                self.assertEqual(errs, []); self.assertLessEqual(len(c), 50)
        unittest.main()
        """, base=HIDDEN)

elif T in ("T8", "T13"):
    pkg_init("pkg", "tests")
    bodies = [
        ("def clamp(value, low, high):\n    return max(low, min(high, value))",
         "def mean(values):\n    return sum(values) / len(values) if values else 0.0",
         "def is_palindrome(text):\n    t = ''.join(c.lower() for c in text if c.isalnum())\n    return t == t[::-1]"),
        ("def word_counts(text):\n    out = {}\n    for w in text.split():\n        out[w] = out.get(w, 0) + 1\n    return out",
         "def chunk(items, size):\n    return [items[i:i + size] for i in range(0, len(items), size)]",
         "def safe_int(text, default=None):\n    try:\n        return int(text)\n    except (TypeError, ValueError):\n        return default"),
        ("def initials(name):\n    return ''.join(p[0].upper() for p in name.split() if p)",
         "def flatten(nested):\n    return [x for sub in nested for x in sub]",
         "def percent(part, whole):\n    return round(100.0 * part / whole, 1) if whole else 0.0"),
        ("def dedupe(items):\n    seen = set()\n    return [x for x in items if not (x in seen or seen.add(x))]",
         "def title_case(text):\n    return ' '.join(w.capitalize() for w in text.split())",
         "def median(values):\n    s = sorted(values)\n    n = len(s)\n    return (s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2) if n else None"),
        ("def invert(mapping):\n    return {v: k for k, v in mapping.items()}",
         "def truncate(text, limit, suffix='...'):\n    return text if len(text) <= limit else text[:max(0, limit - len(suffix))] + suffix",
         "def running_total(values):\n    out, acc = [], 0\n    for v in values:\n        acc += v\n        out.append(acc)\n    return out"),
        ("def parse_bool(text):\n    return str(text).strip().lower() in ('1', 'true', 'yes', 'on')",
         "def pairwise(items):\n    return list(zip(items, items[1:]))",
         "def count_vowels(text):\n    return sum(1 for c in text.lower() if c in 'aeiou')"),
        ("def merge_dicts(a, b):\n    out = dict(a)\n    out.update(b)\n    return out",
         "def nth_prime(n):\n    count, k = 0, 1\n    while count < n:\n        k += 1\n        if all(k % d for d in range(2, int(k ** 0.5) + 1)):\n            count += 1\n    return k",
         "def slug_words(text):\n    return [w for w in text.lower().split('-') if w]"),
        ("def top_n(scores, n):\n    return sorted(scores, key=scores.get, reverse=True)[:n]",
         "def celsius_to_f(c):\n    return c * 9 / 5 + 32",
         "def normalize_spaces(text):\n    return ' '.join(text.split())"),
        ("def group_by_len(words):\n    out = {}\n    for w in words:\n        out.setdefault(len(w), []).append(w)\n    return out",
         "def sign(x):\n    return (x > 0) - (x < 0)",
         "def ends_with_any(text, suffixes):\n    return any(text.endswith(s) for s in suffixes)"),
        ("def rotate(items, k):\n    if not items:\n        return []\n    k %= len(items)\n    return items[k:] + items[:k]",
         "def char_freq(text):\n    out = {}\n    for c in text:\n        out[c] = out.get(c, 0) + 1\n    return out",
         "def between(x, lo, hi):\n    return lo <= x <= hi"),
        ("def last_word(text):\n    parts = text.split()\n    return parts[-1] if parts else ''",
         "def scale(values, factor):\n    return [v * factor for v in values]",
         "def has_duplicates(items):\n    return len(set(items)) != len(items)"),
        ("def weekday_name(i):\n    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i % 7]",
         "def interleave(a, b):\n    out = []\n    for x, y in zip(a, b):\n        out += [x, y]\n    return out",
         "def digits_sum(n):\n    return sum(int(d) for d in str(abs(n)))"),
    ]
    for i, trio in enumerate(bodies, 1):
        with open(os.path.join(REPO, f"pkg/util{i:02d}.py"), "w") as f:
            f.write("\n\n\n".join(trio) + "\n")
    w("tests/test_utils.py", """
        import unittest
        from pkg.util01 import clamp, mean
        from pkg.util05 import running_total
        from pkg.util07 import nth_prime
        from pkg.util10 import rotate


        class T(unittest.TestCase):
            def test_some(self):
                self.assertEqual(clamp(5, 0, 3), 3)
                self.assertEqual(mean([1, 2, 3]), 2)
                self.assertEqual(running_total([1, 2, 3]), [1, 3, 6])
                self.assertEqual(nth_prime(4), 7)
                self.assertEqual(rotate([1, 2, 3], 1), [2, 3, 1])
        """)
    w("hidden_t8.py", """
        import ast, os, sys, subprocess
        repo = sys.argv[1]; bad = []; n = 0
        for i in range(1, 13):
            tree = ast.parse(open(os.path.join(repo, f"pkg/util{i:02d}.py")).read())
            for fn in [x for x in tree.body if isinstance(x, ast.FunctionDef)]:
                n += 1
                if len((ast.get_docstring(fn) or "").split()) < 5: bad.append(f"{fn.name}: docstring")
                anns = [a.annotation for a in fn.args.args] + [fn.returns]
                if any(a is None for a in anns): bad.append(f"{fn.name}: hints missing")
                elif any(ast.unparse(a) in ("Any", "typing.Any") for a in anns): bad.append(f"{fn.name}: vague hint")
        r = subprocess.run([sys.executable, "-m", "unittest", "-q"], cwd=repo, capture_output=True, text=True)
        if r.returncode: bad.append("unittest failed")
        if n != 36: bad.append(f"expected 36 functions, found {n}")
        print("HIDDEN OK" if not bad else "HIDDEN FAIL: " + ", ".join(bad[:8])); sys.exit(1 if bad else 0)
        """, base=HIDDEN)

elif T in ("T9", "T10", "T11"):
    pkg_init("src", "tests")
    w("SPEC.md", """
        # src/intervals.py

        ## merge(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]
        Each interval is (start, end) with start <= end, inclusive. Return the sorted list of
        merged intervals; intervals that overlap or touch (end + 1 == next start) merge.
        Raise ValueError if any interval has start > end. Empty input -> [].

        ## parse(text: str) -> list[tuple[int, int]]
        Parse "1-3,5,7-9" into [(1, 3), (5, 5), (7, 9)]. Whitespace around items is allowed.
        Raise ValueError on anything else ("", "1-", "a", "3-1").

        ## total(intervals) -> int
        Number of distinct integers covered after merging: total([(1,3),(2,5)]) == 5.
        """)
    w("src/intervals.py", """
        def merge(intervals):
            raise NotImplementedError


        def parse(text):
            raise NotImplementedError


        def total(intervals):
            raise NotImplementedError
        """)
    w("hidden_test_intervals.py", """
        import sys, unittest
        sys.path.insert(0, sys.argv.pop(1))
        from src.intervals import merge, parse, total

        class H(unittest.TestCase):
            def test_merge(self):
                self.assertEqual(merge([]), [])
                self.assertEqual(merge([(5, 7), (1, 3), (4, 4)]), [(1, 7)])
                self.assertEqual(merge([(1, 2), (5, 6)]), [(1, 2), (5, 6)])
                with self.assertRaises(ValueError): merge([(3, 1)])
            def test_parse(self):
                self.assertEqual(parse("1-3, 5 ,7-9"), [(1, 3), (5, 5), (7, 9)])
                for bad in ["", "1-", "a", "3-1"]:
                    with self.assertRaises(ValueError, msg=bad): parse(bad)
            def test_total(self):
                self.assertEqual(total([(1, 3), (2, 5)]), 5)
                self.assertEqual(total([(1, 1), (3, 3)]), 2)
        unittest.main()
        """, base=HIDDEN)
else:
    sys.exit(f"unknown scenario {T}")

subprocess.run(["git", "init", "-q"], cwd=REPO, check=True)
subprocess.run(["git", "add", "-A"], cwd=REPO, check=True)
subprocess.run(["git", "-c", "user.email=eval@local", "-c", "user.name=eval", "commit", "-qm", "fixture"], cwd=REPO, check=True)
print(f"fixture {T} ready at {REPO}")
