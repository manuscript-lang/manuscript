#!/usr/bin/env python3
"""Summarize results/runs.jsonl as Markdown tables.

Pass rate counts every run. Tokens, turns, time and cost average over PASSING runs only,
so a cheap wrong answer never improves a language's numbers.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

path = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / "results" / "runs.jsonl")
runs = [json.loads(l) for l in path.read_text().splitlines() if l.strip()] if path.exists() else []
if not runs:
    sys.exit("no runs")

def table(keyfn, title):
    groups = defaultdict(list)
    for r in runs:
        groups[keyfn(r)].append(r)
    print(f"\n### {title}\n")
    print("| group | runs | pass | first build ok | tokens (in+out) | turns | wall s | cost $ |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for k, rs in sorted(groups.items()):
        ok = [r for r in rs if r["pass"]]
        m = lambda f: f"{mean(f(r) for r in ok):.3g}" if ok else "-"  # noqa: E731
        print(f"| {k} | {len(rs)} | {len(ok)/len(rs):.0%} | {sum(r['first_build_ok'] for r in rs)/len(rs):.0%} "
              f"| {m(lambda r: r['usage']['tokens_in'] + r['usage']['tokens_cached'] + r['usage']['tokens_out'])} "
              f"| {m(lambda r: r['usage']['turns'])} | {m(lambda r: r['wall_s'])} | {m(lambda r: r['usage']['cost_usd'])} |")

table(lambda r: f"{r['harness']} / {r['language']}", "By harness and language")
table(lambda r: f"{r['language']} / {r['category']}", "By language and category")
table(lambda r: f"{r['language']} / tier {r['tier']}", "By language and tier")
