#!/usr/bin/env python3
"""Copy an experiment's raw artifacts to a publishable folder, with identifying strings replaced.

usage: sanitize.py RULES_JSON SRC_DIR DST_DIR

RULES_JSON (keep yours outside every repo; see sanitize-rules.example.json):
  {
    "replacements": [["<regex>", "<replacement>"], ...],   applied in order, most specific first
    "deny": ["<regex>", ...]                                 must match nothing after replacing
  }

Every text file under SRC_DIR is copied to the same relative path under DST_DIR with the
replacements applied (Python `re`, case-sensitive unless the pattern says `(?i)`). Then every
output line is checked against the deny patterns (case-insensitive). Exit 0 when clean, 1 when
any deny pattern still matches (each hit is printed with file:line), 2 on a usage error.

A deny-list only finds what you thought to list. After a clean run, also sweep the output for
IP addresses, e-mail addresses and hostnames you didn't expect (README of this repo).
"""
import json
import os
import re
import sys


def load_rules(path):
    with open(path, encoding="utf-8") as handle:
        doc = json.load(handle)
    replacements = [(re.compile(p), r) for p, r in doc.get("replacements", [])]
    deny = [re.compile(p, re.IGNORECASE) for p in doc.get("deny", [])]
    if not deny:
        raise ValueError("rules file has no deny patterns: a run could never fail")
    return replacements, deny


def main(argv):
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    rules_path, src, dst = argv[1:]
    replacements, deny = load_rules(rules_path)
    if os.path.abspath(dst).startswith(os.path.abspath(src) + os.sep):
        print("DST_DIR must not be inside SRC_DIR", file=sys.stderr)
        return 2
    hits = 0
    files = 0
    for root, _dirs, names in os.walk(src):
        for name in sorted(names):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, src)
            try:
                with open(path, encoding="utf-8") as handle:
                    text = handle.read()
            except UnicodeDecodeError:
                print(f"SKIP {rel}: not UTF-8 text (copy or redact it by hand)")
                hits += 1
                continue
            for pattern, repl in replacements:
                text = pattern.sub(repl, text)
            out = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "w", encoding="utf-8") as handle:
                handle.write(text)
            files += 1
            for number, line in enumerate(text.splitlines(), 1):
                if any(d.search(line) for d in deny):
                    hits += 1
                    print(f"DENY {rel}:{number}: {line.strip()[:160]}")
    print(f"sanitize: {files} file(s) written, {hits} problem(s)")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
