# Readable conformance tests

* Status: **Proposed** (2026-11-25, checked against `a3691f89`)
* Authors: [chinmaymk](https://github.com/chinmaymk)
* Implementation: stages 1 and 2a landed (every `check` fixture, 2,816, states its expectation in its file); 2b: `phase=test,parse` replaces 1,183 `-fmt` twins; run and test fixtures follow
* Direction: Chinmay, 2026-11-25: "one suite we test to assert correctness, one suite for perf, one suite for agent-bench"; tests are "littered with .json files so reading code and figuring what it does is crazy hard".

## Summary

- Problem: `tests/` is 15,487 files and 71 MB, 6,315 of them JSON; a fixture's expectation lives in a sidecar a reader must open, and most are snapshots of what the binary printed, not stated intent.
- Change: the expectation moves into the `.ms` file as header lines; sidecar JSON, `-fmt` twins and stored fuzz output go away; names say what is tested.
- Decision requested: approve the format and the stages below.

## Motivation

Measured with a script over `tests/conformance/fixtures` (5,737 expectation files):

| Fact | Count |
| --- | --- |
| Expectation files, `.json` | 5,737 (5.6 MB), plus 1,342 `-fmt.ms` twins |
| Phases | check 2,831, parse 1,461, test 775, run 670 |
| Meaningless names | `snippets/golden/golden-0001` (1,098 checker cases), `benchmarkparsepartial-2` (names from deleted Rust tests) |
| Stored generated output | `fuzz/` 1,456 files, produced by `fuzz-gen`, "do not edit by hand" |
| Duplicate sources (header stripped) | 378 of 3,722 programs |
| Expectations over 2 KB | 592 |

A check fixture's JSON holds the diagnostics, then the same diagnostics again as terminal text with the source line quoted (the `text` field). A parse fixture is a program plus a second `-fmt.ms` file plus two JSON files. `tests/conformance/README.md` says a recorded fixture "records what the binary does, bugs included". `tests/` also holds `checks/` (59 files run by gates), `lsp/` (32 dirs) and `docs/` (JS tests), which a reader cannot tell from the corpus.

## Proposed solution

One file per test; the expectation sits after the program as comments, so the line numbers in them are the editor's (lines added above the program would shift every position and every `at 7:5` inside a message):

```
// conform: phase=check tags=ownership
export fn main() Int {
	var xs = ["hello"]
	ys := xs
	...
}
// expect-error: MS3000 9:9 cannot change `xs` while `ys` borrows it
```

A run test states its output the same way (`// expect-stdout:` lines, or, better, a `test` block with `expect_equal`). `--record` writes these lines and refuses a differing second observation, as it does today. The rendered terminal text is derived from the diagnostics, so it is not stored; a handful of CLI fixtures, chosen in stage 2, keep a stored rendering to pin the layout.

## Detailed design

- **Header lines**: `expect-error: <code> <line>:<col> <message>` (one per diagnostic, message complete), `expect-exit: <n>`, `expect-stdout:` / `expect-stderr:` (one comment line per output line, with escapes only for trailing spaces and `\r`). `oracle` and `format` fields are dropped; the file header already carries `// conform:` metadata.
- **Offsets**: `position.offset` is derived from line and column; the header shifts offsets when edited, which is the README's "re-record after editing tags" hazard, so it disappears.
- **Parse fixtures**: stored already formatted; `ms fmt --check` over the corpus replaces the twin. A fixture that exists to test formatting keeps an explicit input and `.out` pair under `tests/format/` (count taken in stage 2).
- **Fuzz** (open): the 1,206 stored `fuzz/` programs are generator output plus what `ms` printed for each; generating them in the gate would drop that recorded oracle, so they stay until an owner decision on what property replaces it.
- **Names**: harvested `golden-NNNN` cases are renamed `<code>-<first words of the message>` (or `accept-<first code line>`) and exact duplicates are dropped (done in 3a: 1,098 files, 18 duplicates). They stay one program per file, not grouped by code: a group file would lose per-case isolation and make every position depend on its block.
- **Layout**: `tests/lang/` (accept, stdlib, projects, run and test phases), `tests/diagnostics/` (reject and golden, by code), `tests/format/`, `tests/lsp/`, `tests/docs/`. The gate programs in `tests/checks/` move next to their `make` target's tool under `tools/checks/`, so `tests/` holds only the suites.
- **`tests/lang/` is one kind of test**: a `.ms` file of `test` blocks run by `ms test`, grouped by feature (`ownership/`, `lists/`, `modules/`, `faults/`, one directory per stdlib module), not by origin. Measured: of 1,445 run and test fixtures, 400 are stored fuzz output (dropped, generated instead), 775 are already `test` blocks, and 270 are recorded `run` programs (350 of all run outputs are under 200 bytes and exit 0; 121 end in a fault, exit 134). The 270 keep `// expect-stdout:` and `// expect-exit:` headers and become `test` blocks when touched; faults keep `expect-exit`. The `accept`/`stdlib`/`snippets/*` split (names of deleted Rust packages: `checker`, `compiler`, `lower`, `lexer`, `build`) goes away; each case moves to its feature directory by its `tags=`. Only multi-file programs (121 project directories today) keep a directory with `ms.toml`.
- **Runner**: `tools/conform-run.ms` reads headers instead of sidecars; phase logic is unchanged. `make conform` stays the one command; `ms test tests/` runs the `test`-phase files directly.
- **Frozen contracts** ([wiki](../wiki/testing-and-conformance/conformance-expectations-are-frozen-contracts.md)) hold: the conversion is mechanical and lossless apart from the derived text and the dropped duplicates, checked by running both formats on the same binary and diffing results.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `tools/conform/corpus.ms`, `conform-run.ms` | read and write header expectations | unit test of the header round trip; full corpus replay |
| `tests/conformance/fixtures/**` | converted, renamed, regrouped | conform 0 problems, same counts per phase minus dropped duplicates |
| `tools/conform/fuzz_commands.ms` | generate in the gate | gate fails on a seeded bug |
| `tests/checks/**` | moved under `tools/checks/` (done) | the `make` targets that run them |
| wiki, README, AGENTS | one page for the layout | `repo-check` |

## Alternatives

- Do nothing: the cost stays, and every new fixture adds two files.
- Delete the recorded snippets and write real tests: loses 3,600 cases of coverage that pin current behavior; a rewrite by hand would take weeks and is not needed for readability. Kept as the way new tests are written.
- Keep JSON, add a viewer command: still two files per case and a tool needed to read a test.
- A table file per area with many programs in one file: used only for diagnostics grouped by code; elsewhere one program per file keeps `ms check` and editor support working on each.

## Stages

1. Header format in the runner and recorder; convert `e2e/reject` and `snippets/authored` (a few hundred); corpus green.
2. Convert every check fixture (done, with the recorder re-observing until lines that sit after the program stop moving an end-of-file diagnostic). Then parse fixtures and the `-fmt` twins: a twin is its original's source with `phase=parse`, so a fixture should name several phases (`phase=test,parse`) instead of being copied; 1,230 of 1,342 twins state only that `ms fmt` leaves the source unchanged, 112 differ and are mostly fuzz seeds.
3. Regroup `golden` by code and dedupe; generate fuzz in the gate.
4. Move `e2e/*` and `snippets/*` run and test cases into feature directories by tag; convert the 270 recorded runs; move `tests/checks` (done); one README and wiki page.

Each stage lands green and keeps `make conform` as the gate (its time must not grow).

## Open questions

- Is dropping the stored terminal text acceptable, given a few kept CLI renderings? Recommendation: yes; it is derived from fields already stored.
- Hand-written tests only from now on for new behavior, with `--record` allowed for diagnostics only? Recommendation: yes.
