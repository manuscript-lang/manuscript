# ms-bench

Measures how effectively coding agents solve the same programming challenges in TypeScript, Go, Rust and
Manuscript. Per run it records pass/fail against hidden tests, tokens, turns, wall time and cost.

Status: 50 challenges x 4 languages with reference solutions. Runs through Harbor (preferred) or the built-in runner.

## How a run works

1. A fresh workspace is created outside the repo: language template, `TASK.md` (the spec), a few visible
   examples in `examples/`, and `check.sh`. For Manuscript the tutorials and standard declarations are copied
   to `docs/` (`context` in `languages.json`).
2. The harness runs the agent non-interactively in that workspace. The agent is told to use `./check.sh`,
   which builds and runs the examples and logs each attempt to `.bench/log.jsonl`. That log gives
   harness-independent build counts and a first-build-success flag.
3. After the agent exits, the runner builds the workspace and runs the **hidden cases** (`challenges/*/hidden/`),
   which are never copied into the workspace. Output is compared exactly, ignoring trailing whitespace.
4. One JSON line is appended to `results/runs.jsonl`; the raw transcript goes to `results/transcripts/` (gitignored).

A run **passes** only if every hidden case passes. `report.py` computes tokens, turns, time and cost over
passing runs only, so a cheap wrong answer never improves a language's numbers; pass rate and first-build rate
cover all runs.

## Commands

```sh
python3 ms-bench/run.py list
python3 ms-bench/run.py oracle                     # reference solutions vs hidden cases; validates the suite
python3 ms-bench/run.py run --harness claude_code --model <model> \
    --challenges c01,c02 --languages ms,go --repeat 3 --tag baseline
python3 ms-bench/report.py                         # Markdown tables from results/runs.jsonl
python3 -m unittest discover -s ms-bench/tests
```

`ms`, `go`, `cargo` and `node` (22+) must be on `PATH`. Build `ms` with `make build` and add the repo root to `PATH`.

## Running through Harbor

[Harbor](https://docs.harborframework.com) provides the agents (`claude-code`, `codex`, `pi` are pre-integrated), sandboxes, parallelism and result files.
`export_harbor.py` turns every challenge x language into a Harbor task; the hidden cases go only into `tests/`.

```sh
python3 ms-bench/export_harbor.py --out /tmp/ms-bench-tasks --ms-binary ./ms
harbor run -p /tmp/ms-bench-tasks -a claude-code -m claude-haiku-5-5 -o jobs     # Docker or any Harbor sandbox
```

Without Docker, use the local-process environment (not a sandbox; the toolchains must be on `PATH`):

```sh
PYTHONPATH=ms-bench/harbor harbor run -p /tmp/ms-bench-tasks/c01-word-frequency-ms -a claude-code \
    -m claude-haiku-5-5 --env local_env:LocalProcessEnvironment -o jobs
```

The verifier (`harbor/grade.py`) writes reward 1 only when every hidden case passes, and `detail.json` with passed/total
cases and first-build success. Harbor records tokens and cost per trial. Use `-a oracle` to check the reference solutions.

## Layout

| path | purpose |
| --- | --- |
| `languages.json` | per-language build/run commands, solution file, extra context |
| `templates/<lang>/` | starting workspace per language |
| `challenges/<id>/` | `challenge.json`, `spec.md`, `examples/`, `hidden/`, `solutions/<lang>/<file>.ref` (reference), `gen.py` (derives cases from a Python oracle) |
| `harnesses/` | one adapter per agent CLI |
| `core/` | challenge loading, workspace construction, grading |
| `pricing.json` | token prices, used only when a harness reports no cost |
| `results/runs.jsonl` | one record per run |

## Extending

- **Challenge**: add `challenges/cNN-name/` with the files above. Contract: stdin to stdout, exact output. Run
  `python3 challenges/cNN-name/gen.py`, write all four reference solutions, then `run.py oracle`.
- **Language**: add an entry to `languages.json`, a `templates/<id>/` dir, and a reference solution per challenge.
- **Harness**: subclass `Harness` in `harnesses/` (`command()` builds argv, `parse()` returns `Usage`) and register it
  in `harnesses/__init__.py`. If the CLI reports no cost, leave `cost_source` as `none` and the base class estimates it.

## Known limits

- Only the Claude Code adapter has been run. The Codex and pi adapters are written from their documented
  JSON event streams and are **untested**; check them against real output before trusting numbers.
- Workspaces are separate directories, not sandboxes. An agent with filesystem access could find `hidden/`.
  Runs whose transcript mentions the challenge tree are flagged `suspect_peek`; for real runs use a container
  that mounts only the workspace.
- Wall time includes model latency, so compare it within a harness and model, not across them.
- Manuscript's current runtime performance affects tests with large inputs (see `c04-lru-cache`); timeouts are
  set per challenge in `challenge.json`.
- Runs are sequential. Parallelism and cross-run seeds for model sampling are not implemented.
