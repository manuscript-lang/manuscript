# agent-bench

Not the performance benchmark: for compiler/runtime speed against hand-written Go, see [`bench/perf/`](../bench/perf/README.md). Results here never mix with those.

Agent benchmark: measures how effectively coding agents solve the same programming challenges in TypeScript, Go, Rust and
Manuscript. Per run it records pass/fail against hidden tests, tokens, turns, wall time and cost.

Status: 20 challenges: 10 small programs (c03-c44, with reference solutions in all four languages) and 10 large applications of roughly 3-5k lines (c51-c60), which have no reference solutions and are validated only through the Go oracle in each challenge's `oracle/` directory (see its `gen.py`, which derives the expected outputs deterministically). One trial per challenge and language. Runs through Harbor (preferred) or the built-in runner.

Report source size as LLM tokens (`llm_tokens` in each run, from `pip install tiktoken`; final sources are saved under `results/sources/`), never lexical tokens (`code_tokens`). `ms run bench/agent/tokens.ms` compares the reference solutions per language.

## How a run works

1. A fresh workspace is created outside the repo: language template, `TASK.md` (the spec), a few visible
   examples in `examples/`, and `check.sh`. For Manuscript the tutorials and standard declarations are copied
   to `docs/` when a language lists `context` in `languages.json`; Manuscript lists none and points the agent at `ms guide` and `ms search_symbol`.
2. The harness runs the agent non-interactively in that workspace. The agent is told to use `./check.sh`,
   which builds and runs the examples and logs each attempt to `.bench/log.jsonl`. That log gives
   harness-independent build counts and a first-build-success flag.
3. After the agent exits, the runner builds the workspace and runs the **hidden cases** (`challenges/*/hidden/`),
   which are never copied into the workspace. Output is compared exactly, ignoring trailing whitespace.
4. One JSON line is appended to `results/runs.jsonl`; the raw transcript goes to `results/transcripts/` (gitignored).

A run **passes** only if every hidden case passes. `report.ms` computes tokens, turns, time and cost over
passing runs only, so a cheap wrong answer never improves a language's numbers; pass rate and first-build rate
cover all runs.

## Commands

```sh
ms run bench/agent/run.ms -- list
ms run bench/agent/run.ms -- oracle                     # reference solutions vs hidden cases; validates the suite
ms run bench/agent/run.ms -- run --harness claude_code --model <model> \
    --challenges c03,c05 --languages ms,go --repeat 3 --jobs 4 --tag baseline
ms run bench/agent/report.ms --                         # Markdown tables from results/runs.jsonl
ms test bench/agent/core_test.ms
```

`ms`, `go`, `cargo` and `node` (22+) must be on `PATH`. Build `ms` with `make build` and add the repo root to `PATH`.

## Running through Harbor

[Harbor](https://docs.harborframework.com) provides the agents (`claude-code`, `codex`, `pi` are pre-integrated), sandboxes, parallelism and result files.
`export_harbor.ms` turns every challenge x language into a Harbor task; the hidden cases go only into `tests/`.

```sh
ms run bench/agent/export_harbor.ms -- --out /tmp/agent-bench-tasks --ms-binary ./ms
harbor run -p /tmp/agent-bench-tasks -a claude-code -m claude-haiku-5-5 -o jobs     # Docker or any Harbor sandbox
```

Without Docker, use the local-process environment (not a sandbox; the toolchains must be on `PATH`). `harbor/local_env.py` is the only Python left in this directory: Harbor loads environment classes as Python plugins.

```sh
PYTHONPATH=bench/agent/harbor harbor run -p /tmp/agent-bench-tasks/c03-csv-group-sum-ms -a claude-code \
    -m claude-haiku-5-5 --env local_env:LocalProcessEnvironment -o jobs
```

The verifier (`grade.ms`, run with the `ms` binary baked into each task image) writes reward 1 only when every hidden case passes, and `detail.json` with passed/total
cases and first-build success. Harbor records tokens and cost per trial. Use `-a oracle` to check the reference solutions.

## Layout

| path | purpose |
| --- | --- |
| `languages.json` | per-language build/run commands, solution file, extra context |
| `templates/<lang>/` | starting workspace per language |
| `challenges/<id>/` | `challenge.json`, `spec.md`, `examples/`, `hidden/`, `solutions/<lang>/<file>.ref` (reference), `gen.ms` (derives cases from the reference solutions or, for c51-c60, the Go oracle) |
| `harnesses/` | one adapter per agent CLI |
| `core/` | challenge loading, workspace construction, grading |
| `pricing.json` | token prices, used only when a harness reports no cost |
| `results/runs.jsonl` | one record per run |

## Extending

- **Challenge**: add `challenges/cNN-name/` with the files above. Contract: stdin to stdout, exact output. Run
  `ms run bench/agent/gen.ms -- cNN` (add the challenge to `gen.ms`), write all four reference solutions, then `ms run bench/agent/run.ms -- oracle`.
- **Language**: add an entry to `languages.json`, a `templates/<id>/` dir, and a reference solution per challenge.
- **Harness**: implement the `Harness` interface from `harnesses/harness.ms` in a new file (`command()` builds argv, `parse()` returns `Usage`) and register it
  in `harnesses/all.ms`. If the CLI reports no cost, leave `cost_source` as `none` and the base class estimates it.

## Results

Results are kept in date-named files: `results/trials-YYYY-MM-DD.jsonl` (one line per trial) and `results/leaderboard-YYYY-MM-DD.md`. Earlier dates stay as history; never overwrite one. Render with `ms run bench/agent/leaderboard.ms -- collect JOBS_DIR... && ms run bench/agent/leaderboard.ms -- render`. A resumed or repeated job keeps only the latest trial per challenge, language, agent and model.

`agent tokens` is what the agent consumed (input including cache reads, plus output). `solution size (tokens)` is the number of lexical tokens (identifiers, literals and punctuation; comments excluded) in the final source the agent left in the workspace, computed by `core/codetokens.ms` in the verifier. It is language-neutral, not any model's tokenizer count, and `n/a` for runs that predate it.

Every bench report includes a comparison with the other languages (pass rate, first build, agent tokens, solution size, turns, wall time, cost), even when only Manuscript was rerun; use the latest earlier results for the others and say which date they come from.

The 2026-10-18 baseline is Claude Code with Haiku (`claude-haiku-5-5`), one trial per challenge and language (80 trials), against Manuscript compiler `2dc8d488`, run through Harbor with the local-process environment and 6 trials in parallel. Agent timeouts are graded and count as failures. Wall time was measured under parallel load.

The 2026-10-14 baseline predates the specs tightened afterwards for c52, c55, c58, c59 and c60 (several cases failed in most languages because the spec left oracle behaviour unstated), so those challenges' results there have not been re-run.

## Known limits

- Only the Claude Code adapter has been run. The Codex and pi adapters are written from their documented
  JSON event streams and are **untested**; check them against real output before trusting numbers.
- Workspaces are separate directories, not sandboxes. An agent with filesystem access could find `hidden/`.
  Runs whose transcript mentions the challenge tree are flagged `suspect_peek`; for real runs use a container
  that mounts only the workspace.
- Wall time includes model latency, so compare it within a harness and model, not across them.
- Manuscript's current runtime performance affects tests with large inputs (see `c04-lru-cache`); timeouts are
  set per challenge in `challenge.json`.
- Cross-run seeds for model sampling are not implemented. `--jobs N` runs trials in parallel; wall time then reflects contention, so compare it only within one `--jobs` setting.
