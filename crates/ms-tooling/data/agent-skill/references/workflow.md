# Workflow

How a Manuscript change goes from request to shipped, for one file or a whole project. The loop is always: orient, model, write, check, test, verify, ship. Each step has one command.

## Choose the shape

- **One file** (a script, a probe, an exercise): `main.ms` alone. Run with `ms run main.ms -- args`. No manifest needed; `ms verify main.ms` gates it.
- **A project** (several modules, tests, packages, a binary): `ms init <name>` creates `ms.toml`, `src/main.ms`, `test.ms`, `.gitignore`. Then use `ms check`, `ms run -- args`, `ms test`, `ms verify` from its directory (they default to `ms.toml`). `ms init --lib <name>` makes a library with no `entry`.
- **A repository of several projects**: a `[workspace]` root; see [Projects and packages](projects-and-packages.md).

## Orient before writing

1. Read the file you will change, its tests, and `ms.toml`. Match naming, error kinds and layout already there.
2. Find what exists instead of writing it: `ms search_symbol <words>` searches the project and the standard library and prints signatures and import lines. `ms search_symbol json` shows a module's page; `ms search_symbol List.sorted` one call. The [module map](standard-modules.md) lists every `@std` file.
3. Run `ms check ms.toml` first. A clean start tells you later errors are yours.

## Design from the data out

Write in this order, checking after each step:

1. **Types and enums** for the facts and states. Use defaults for optional fields; give an enum case a payload only for what that state needs.
2. **Signatures** for the operations, deciding ownership: plain parameter to read, `var` to change, `move` to take. Return `T!` for what can fail, `T?` for what may be absent, `Void` only when there is nothing to report.
3. **Bodies**, small functions, early exits (`if bad: return error(...)`), pipelines for derived values, flat `match`.
4. **`main`** last: parse arguments, call the core, print, return `Void!` so any error prints and exits 1.

Keep a pure core and a thin edge. The core takes values and returns values; `main` reads files, prints, and builds capabilities (see the effects section of the [mental model](mental-model.md)). The core is then easy to test without files or a network.

## Lay out a project

```
store/
  ms.toml            [project] name, source = "./src", entry = "./src/main.ms"
  src/main.ms        argument handling and wiring only
  src/domain/*.ms    types, rules (export what others import)
  test.ms            cross-module tests; each module also keeps its own `test` blocks
```

Import by relative path inside the project, by alias for stable names (`[aliases] "@domain" = "./src/domain"`), and by `@std/...` for the standard library. Always write `.ms`. No cycles, no wildcard imports. Export only what other modules need.

## Check, correct, format

```sh
ms check --fix ms.toml     # type, ownership, exhaustiveness; applies mechanical repairs
ms fmt ms.toml             # rewrites files canonically
ms lint ms.toml            # effects, unused values, flat-match style
```

- A diagnostic reads `<cause>; <fix>`. Do what it says; if the fix needs a decision it explains. `ms explain <code>` expands a code (`MSL116`, `MSN001`); `--json` gives structured output.
- `--fix` can add `.wait()` or fix a name; it does not write `match` arms or decide ownership. Re-read the file after `--fix` or `fmt`, which rewrite it.
- When an error cites ownership, fix the signature or the store, not the symptom: clone where a value is kept, `move` where a function takes it, `var` where it changes.

## Change existing code

- Add an enum case, then run `ms check`: it lists every `match` to update. Add the arms by hand, each meaningful, not a blanket `_:`.
- Change a signature, then fix each call the checker reports. Keep behavior outside the request unchanged.
- Add or adjust a `test` for the behavior you touched, and run it before and after the change when you can.
- Prefer deleting a duplicated helper to adding a second one. Prefer a standard-library call (`ms search_symbol`) to a hand-written loop.

## Run, observe, verify

1. `ms run <file or ms.toml> -- args` and look at real output for a normal input, an empty input and a bad input. Passing `check` proves types and ownership, not behavior.
2. `ms test ms.toml` ([Testing](testing.md)).
3. `ms verify --deny-warnings` runs checker, formatter check, lint and tests, and returns one status. Loop until it is zero.
4. Report what was run and what was not; do not claim a pass for a command you did not run.

## Packages and shipping

- Add a dependency: `ms add <git url> --version 1.2 --allow` (or `--tag`, `--sha <40 hex>`). It edits `ms.toml` and `ms.lock` and shows the effects the package may reach; commit `ms.lock`. `ms install` restores everything after a clone. Only `add`, `install` and `remove` use the network.
- Ship: `ms build ms.toml -o prog` (debug, fast to build) or `ms build ms.toml --build-type Release -o prog`. The binary runs without `ms`. Pass arguments after `--` to `ms run`, directly to the binary.
- Review a diff before sharing: `git diff main | ms review ms.toml --diff -` ranks changed contracts, error flow, resource scopes and new effects. `ms diagram ms.toml --format html -o code-map.html` writes an offline map.

## A tiny project, end to end

<!-- complete: workflow-wc.ms -->
```manuscript
import (
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Counts:
	lines: Int
	words: Int
	bytes: Int

fn count(text: String) Counts:
	return Counts(
		lines: text.lines().length(),
		words: text.fields().length(),
		bytes: text.length(),
	)

// ms: allow_effect std.fs.read
fn load(path: String) String!:
	raw := read_file(path).wait()?
	return raw.decode_utf8().ok_or(Error(f"{path} is not UTF-8", kind: "EBADMSG"))

fn main() Void!:
	path := arguments().first().ok_or(Error("usage: wc <file>", kind: "EINVAL"))?
	counts := count(load(path)?)
	print(f"{counts.lines} {counts.words} {counts.bytes} {path}")

test "count words, lines and bytes":
	counts := count("one two\nthree\n")
	expect_equal(counts.lines, 2)?
	expect_equal(counts.words, 3)?
	expect_equal(counts.bytes, 14)?
```

The core (`count`) is pure and tested; `load` and `main` are the edge. `ms run wc.ms -- notes.txt` runs it, `ms test wc.ms` runs the test, `ms verify wc.ms --deny-warnings` gates it.
