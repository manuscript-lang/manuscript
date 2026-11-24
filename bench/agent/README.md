# agent-bench

Not the performance benchmark: for compiler/runtime speed against hand-written Go, see [`bench/perf/`](../perf/README.md). Results here never mix with those.

Agent benchmark: measures how effectively coding agents solve the same programming challenges in TypeScript, Go, Rust and
Manuscript. Per run it records pass/fail against hidden tests, tokens, turns, wall time and cost.

Status: 26 challenges: 10 small programs (c03-c44, with reference solutions in all four languages), one mid-size program (c61, a dependency resolver of about 300 lines in Go), one edit task (c63, below) and 10 large applications of roughly 3-5k lines (c51-c60), which have no reference solutions and are validated only through the Go oracle in each challenge's `oracle/` directory (see its `gen.py`, which derives the expected outputs deterministically). Run each cell at least three times (`--repeat 3`); the report gives 95% confidence intervals, and a cell with one trial proves nothing. Runs through Harbor (preferred) or the built-in runner.

Report source size as LLM tokens (`llm_tokens` in each run, from `pip install tiktoken`; final sources are saved under `results/sources/`), never lexical tokens (`code_tokens`). `ms run bench/agent/tokens.ms` compares the reference solutions per language.

## How a run works

1. A fresh workspace is created outside the repo: language template, `TASK.md` (the spec), a few visible
   examples in `examples/`, and `check.sh`. For Manuscript the tutorials and standard declarations are copied
   to `docs/` when a language lists `context` in `languages.json`; Manuscript lists none. Its `setup` command installs the latest released Manuscript agent skill (`install-skill.sh`) into the workspace, so the agent sees what a user's agent sees; to try an unreleased skill, build it with `sh cmake/toolchain/package-skill.sh <dir>`, serve `<dir>` and set `MS_RELEASE_URL`; `ms search_symbol` finds standard-library APIs.
2. The harness runs the agent non-interactively in that workspace. The agent is told to use `./check.sh`,
   which builds and runs the examples and logs each attempt to `.bench/log.jsonl`. That log gives
   harness-independent build counts, a first-build-success flag, and the diagnostic codes of each failed build (the language's `codes` command in `languages.json`; Go has none and reports its error class, TypeScript has no build step so it never fails a first build).
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
ms run bench/agent/report.ms -- results/trials-*.jsonl   # Markdown tables with 95% CIs, per-challenge matrix, diagnostic-code ranking
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
| `languages.json` | per-language build/run commands, solution file, `setup` (skill install), `codes` (diagnostic extraction), extra context |
| `templates/<lang>/` | starting workspace per language |
| `challenges/<id>/` | `challenge.json`, `spec.md`, `examples/`, `hidden/`, `solutions/<lang>/<file>.ref` (reference), `gen.ms` (derives cases from the reference solutions or, for c51-c60, the Go oracle) |
| `harnesses/` | one adapter per agent CLI |
| `core/` | challenge loading, workspace construction, grading |
| `pricing.json` | token prices, used only when a harness reports no cost |
| `results/runs.jsonl` | one record per run |

## Extending

- **Challenge**: add `challenges/cNN-name/` with the files above. Contract: stdin to stdout, exact output. Run
  `ms run bench/agent/gen.ms -- cNN` (add the challenge to `gen.ms`), write all four reference solutions, then `ms run bench/agent/run.ms -- oracle`.
- **Edit challenge**: the agent changes an existing program instead of writing one. Put the starting program for each language in `challenges/cNN-name/start/<language>/` (laid out as in the workspace, such as `src/main.rs`); it is copied over the template and the prompt tells the agent to change it, keeping other behavior. `spec.md` is the change ticket. Generate the cases from a Go oracle that implements the changed program (see c63, which starts from c13's reference solutions), and check that the starting programs fail most hidden cases. An edit agent may never run `./check.sh`; the report leaves such runs out of the first-build rate.
- **Larger edit challenges (c64 to c67)**: each extends a large application (c57, c56, c52, c60) with a new feature, starting from a passing Sonnet solution of the original task in Manuscript, Rust and Go (600 to 2000 lines in one file; TypeScript has no starting program). The hidden cases are the original task's cases (behavior that must survive) plus scenarios for the change; `spec.md` is the change ticket. The starting programs fail only the new scenarios, and c64 also changes one old case on purpose (a program that recurses deeper than 64 calls now traps with `call depth exceeded`). These are single-file programs; a several-file starting program is still to do.
- **Compiler crashes**: a trial whose transcript, last build output or grading build mentions an internal error or a Rust panic keeps its whole workspace (without `target`, `node_modules`, `.git`) in `results/ice/<run_id>/` (git-ignored), and the runner prints the path. Attach that directory to the compiler issue.
- **First-build errors**: when a trial's first `./check.sh` build fails, the full build output and the sources it was given are saved to `results/first-builds/<run_id>/` (`error.txt`, `src/`; git-ignored). Use them to count which names agents guess wrong.
- **Long challenge**: a challenge that needs more than the run's agent limit sets `agent_timeout_s` in its `challenge.json` (c55 uses 3600).
- **Language**: add an entry to `languages.json`, a `templates/<id>/` dir, and a reference solution per challenge.
- **Harness**: implement the `Harness` interface from `harnesses/harness.ms` in a new file (`command()` builds argv, `parse()` returns `Usage`) and register it
  in `harnesses/all.ms`. If the CLI reports no cost, leave `cost_source` as `none` and the base class estimates it.

## Results

Results are not committed. Run output goes to `results/` (git-ignored), and the maintainers keep dated results outside the repository. First-build counts mostly measure how much a model already knows a language, not how good the language is, so a committed ranking misleads agents that read this repository. Do not add result pages, leaderboards or per-language comparisons here.

Render a run with `ms run bench/agent/leaderboard.ms -- collect JOBS_DIR... && ms run bench/agent/leaderboard.ms -- render`. `agent tokens` is what the agent consumed (input including cache reads, plus output). `solution size (tokens)` is the number of lexical tokens (comments excluded) in the final source the agent left in the workspace, computed by `core/codetokens.ms`.

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
