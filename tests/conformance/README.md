# Conformance corpus

Programs paired with expectations first recorded from the Go `ms`. The expectations are now frozen: they are the contract, and the Go `ms` is no longer needed to check or extend the corpus. The Rust `ms` passes it apart from fixtures tagged `aliasing`, which the value-semantics migration changes on purpose, and the entries in `rust-expect-fail.txt`.

```sh
make conform-rust                            # builds the Rust ms and ms-conform, then gates the corpus
cargo build -p ms-conform
ms-conform run --ms path/to/rust-ms --exclude-tag aliasing --markdown report.md
```

## Layout

`fixtures/<category>/<slug>.ms` is a single-file fixture with `<slug>.expected.json` beside it. A project fixture is a directory holding `conform.meta`, `ms.toml`, sources and `expected.json`. Categories: `go-tests/` (snippets embedded in Go tests), `e2e/`, `examples/`, `bench/`, `docs/` (documentation fences), `repo/`, `fuzz/` (generated).

Metadata lives in `# conform: key=value` lines at the top of the file (or in `conform.meta`): `tags`, `phase`, `origin`, `args` (JSON array), `timeout` (seconds), `entry`, `deterministic`. The header is part of the source, so diagnostic positions are those of the file as stored.

## Phases

| phase | command | compared |
| --- | --- | --- |
| `parse` | `ms check --json`, `ms fmt` | parse-phase diagnostics, formatted source |
| `check` | `ms check --json`, `ms check` | diagnostics (code, phase, message, position), terminal text, exit status |
| `run` | `ms run` | stdout, stderr, exit status |
| `test` | `ms test --json` | per-test results, summary, report shape (durations stripped) |

Paths under the work directory print as `<DIR>`.

## Tags

Feature: `lexer layout parser formatter types generics interfaces closures match destructuring try-result optional with-cleanup faults strings lists maps sets numbers decimal interpolation records alternatives control-flow functions modules projects diagnostics mutation json-protocol docs examples testing cli`; standard library: `stdlib-<module>`; kind: `perf fuzz bench`.

Tier (what a Rust milestone needs): `tier-core` imports nothing, `tier-stdlib` imports only pure modules, `tier-io` touches files, network, processes, time or randomness. Phase 1 of the plan runs `--tag tier-core`.

`aliasing` marks programs whose answer may depend on assignment sharing or `.clone()`. The harvester tags by heuristic (over-tagging is safe); these fixtures are excluded from the Rust gate and migrated with `ms migrate`. Review the tagged set, and tag by hand where the heuristic misses, with `# conform: tags=...,aliasing`.

## Commands

`run`, `record`, `diff`, `list`, `stats`, `lint`, `harvest`, `fuzz-gen`, `fuzz`; `ms-conform --help` lists the options. Useful ones:

- Selection: `--tag`, `--exclude-tag`, `--phase`, `--id`, `--shard i/n`, `--jobs`, `--timeout-scale`.
- `run --expect-fail FILE` allows the listed ids (or `prefix*`); `--write-expect-fail FILE` writes the current failures; `--strict` also fails on entries that now pass; `--json` and `--markdown` write reports with pass rates per tag and phase.
- `diff --a X --b Y` runs two binaries on the corpus and compares them directly, without recorded expectations.
- `fuzz` generates programs, runs the oracle and the binary under test, and compares; `--save DIR` keeps disagreements.

## Adding and refreshing fixtures

1. Write the `.ms` file with a header (or run `harvest`), choose tags and phase.
2. `ms-conform record --ms ./ms --id <slug>` writes the expectation; each fixture runs twice and is refused if the answers differ (`deterministic=true` skips this for time- or random-dependent output you have normalized). `--prune` deletes fixtures that cannot be recorded.
3. `ms-conform lint` checks metadata, unknown tags, orphaned expectations.
4. Review the expectation. It records what Go does, bugs included; a fixture that pins a Go bug keeps its expectation and joins the Rust gate's `--expect-fail` file with a reason.
5. Fixtures whose Go output varies between runs (for example diagnostics emitted in map order) must be deleted, not recorded: one was found this way, `MS3040` ordering for a recursive generic field default, and removed.

## Hostile fixtures

Programs importing `http`, `net`, `tls`, `websocket`, `sse`, `process`, `terminal`, `system`, `random` or `time` are checked but not run by the harvester, since they bind sockets, wait on signals or depend on the clock. Add run fixtures for them by hand with deterministic output.

`make conform-rust CONFORM_SHARD=i/n` replays the corpus against the Rust `ms`; CI runs it in four shards. `make conform-oracle` still re-checks the frozen expectations against the Go `ms` locally until the Go code is removed. Changing a fixture's `# conform:` header shifts byte offsets in its diagnostics, so re-record after editing tags by hand (`ms-conform retag` only touches `tier-*`; run `record` after it).
