[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Source-size gap versus TypeScript is lines and I/O ceremony, not syntax noise

Verified (2026-10-22, o200k_base): `bench/agent/tokens.py` puts the hand-written reference solutions at ms 12.2k, rust 10.1k, go 10.1k, ts 8.3k tokens, so Manuscript is not below Rust (1.21x) or TypeScript (1.48x); the old ms references predate `xs[i]`, `+=`, and inline suites, so they overstate it. Agent-written ms was 1.30x TypeScript. Newlines and indentation account for about 40% of the gap (ms programs run about 1.75x the lines), and agents ignore forms the cheat sheet never showed: `xs[i]`, one-line `if c: return x`, no `flush()`. Reading stdin and the `run()`/`main()` match ceremony cost about 100 tokens per program. Blank lines are free (`\n\n` replaces `\n`). Open options, not decisions: `main` returning `Result`, `try` on `Optional`, a less vertical formatter for call arguments.

Apply when: judging a syntax or stdlib change by its token effect; measure with `tokens.py` and a rerun, not intuition.
Evidence: [tokens.py](../../bench/agent/tokens.py), [cheat sheet](../crates/ms-tooling/src/guide/data/cheatsheet.md), [streams.read_lines](../../stdlib/streams.ms).
Verify: `python3 bench/agent/tokens.py` prints the per-language totals; rerun the small challenges and compare `llm_tokens` of passing ms and ts runs.
