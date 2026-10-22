#!/usr/bin/env python3
"""Source size in LLM tokens (tiktoken o200k_base) per language over the reference solutions.

Usage: python3 bench/agent/tokens.py [--sources DIR]   # needs `pip install tiktoken`
The reference table shows how verbose each language is when the same program is written by hand;
agent-written sizes come from `llm_tokens` in results/runs.jsonl (see README).
"""
import glob
import os
import sys

import tiktoken

HERE = os.path.dirname(os.path.abspath(__file__))
LANGS = ["ts", "rust", "go", "ms"]
enc = tiktoken.get_encoding("o200k_base")


def count(path):
    with open(path, encoding="utf-8") as f:
        return len(enc.encode(f.read()))


def main():
    totals = dict.fromkeys(LANGS, 0)
    print("challenge".ljust(26) + "".join(l.rjust(8) for l in LANGS) + "  ms/ts")
    for challenge in sorted(glob.glob(os.path.join(HERE, "challenges", "c*"))):
        row = {}
        for lang in LANGS:
            refs = glob.glob(os.path.join(challenge, "solutions", lang, "*.ref"))
            if not refs:
                break
            row[lang] = count(refs[0])
        else:
            for lang in LANGS:
                totals[lang] += row[lang]
            print(os.path.basename(challenge).ljust(26) + "".join(str(row[l]).rjust(8) for l in LANGS) + f"  {row['ms'] / row['ts']:.2f}")
    print("total".ljust(26) + "".join(str(totals[l]).rjust(8) for l in LANGS) + f"  {totals['ms'] / totals['ts']:.2f}")
    print(f"ms/rust {totals['ms'] / totals['rust']:.2f}")


if __name__ == "__main__":
    sys.exit(main())
