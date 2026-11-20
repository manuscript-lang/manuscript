#!/usr/bin/env python3
"""Fails when a static function body (60 characters or more once whitespace is folded) is copied into a second
C file of runtime/ or compiler/. Share it through a header instead. toolchain/c-duplicates-pending.txt lists
function names that are known copies; a listed name that no longer repeats must be removed, so the list only
shrinks. Tests and third_party are not checked. Usage (from the repository root): c-duplicates.py"""
import collections, os, re, sys

ROOTS = ("runtime", "compiler")
SKIP = ("third_party", "/tests/", "/fuzz/")
MIN_BODY = 60
HEAD = re.compile(r"^static\s+(?:inline\s+)?[\w\s\*]+?\b(\w+)\(([^;{]*?)\)\s*\{", re.M)

def functions(path):
    text = open(path, errors="replace").read()
    for match in HEAD.finditer(text):
        depth, at = 1, match.end()
        while depth and at < len(text):
            depth += (text[at] == "{") - (text[at] == "}")
            at += 1
        body = re.sub(r"\s+", " ", re.sub(r"/\*.*?\*/|//[^\n]*", "", text[match.end():at], flags=re.S)).strip()
        yield match.group(1), body

def main():
    seen = collections.defaultdict(set)
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            if any(part in directory + "/" for part in SKIP):
                continue
            for name in names:
                if name.endswith((".c", ".h")):
                    path = os.path.join(directory, name)
                    for function, body in functions(path):
                        if len(body) >= MIN_BODY:
                            seen[body].add((function, path))
    repeated = {}
    for body, places in seen.items():
        if len({path for _, path in places}) > 1:
            for function, _ in places:
                repeated.setdefault(function, sorted(path for _, path in places))
    pending = set()
    if os.path.exists("toolchain/c-duplicates-pending.txt"):
        pending = {line.strip() for line in open("toolchain/c-duplicates-pending.txt") if line.strip() and not line.startswith("#")}
    failed = False
    for function, paths in sorted(repeated.items()):
        if function not in pending:
            print("c-duplicates: %s has the same body in %s; share it through a header" % (function, ", ".join(paths)))
            failed = True
    for function in sorted(pending - set(repeated)):
        print("c-duplicates: %s is listed in c-duplicates-pending.txt but no longer repeats; remove it" % function)
        failed = True
    return 1 if failed else 0

sys.exit(main())
