# Workflow

## Shape
- **One file:** `main.ms`; `ms run main.ms -- args`; gate with `ms verify main.ms`.
- **Project:** `ms init <name>` (`ms.toml`, `src/main.ms`, `test.ms`); then `ms check`, `ms run -- args`, `ms test`, `ms verify` from its directory. `--lib` makes a library. Several projects: a `[workspace]` ([Projects](projects-and-packages.md)).

## Loop
1. **Orient.** Read the file, its tests and `ms.toml`; match their style. `ms search_symbol <words>` finds APIs and import lines (`ms search_symbol json` shows a module). Start with a clean `ms check`.
2. **Model.** Types and enums, then signatures (ownership, `T!`/`T?`), then bodies, then a thin `main`. Check after each step. Keep the core pure; `main` reads, prints and builds capabilities.
3. **Check.** `ms check --fix`, `ms fmt`, `ms lint`. Fix by the message; `ms explain <code>` expands it, `--json` is structured. `--fix` and `fmt` rewrite the file: re-read it. Fix ownership errors at the signature or the store, not the symptom.
4. **Test and run.** [Testing](testing.md). Run on a normal, an empty and a bad input and read the output.
5. **Verify.** `ms verify --deny-warnings`. Report what you ran and did not run.
6. **Ship.** `ms build ms.toml -o prog` (add `--build-type Release` to optimize). Review a diff with `git diff main | ms review ms.toml --diff -`.

## Changing code
Add an enum case, then add each arm `ms check` reports by hand (no blanket `_:`). Change a signature, then fix each reported call. Add a test for what you changed. Delete a duplicate helper rather than add a second.

## Layout and packages
`src/main.ms` wiring only; `src/domain/*.ms` types and rules; `test.ms` cross-module tests (modules keep their own `test` blocks). Import with `./x.ms`, an alias (`[aliases] "@domain" = "./src/domain"`) or `@std/...`; always write `.ms`; export only what others import. Add a dependency with `ms add <git url> --version 1.2 --allow`, commit `ms.lock`; only `add`, `install` and `remove` use the network.

## End to end
The pure core (`count`) is tested; `load` and `main` are the edge. `ms run wc.ms -- notes.txt`, `ms test wc.ms`, `ms verify wc.ms --deny-warnings`.

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
