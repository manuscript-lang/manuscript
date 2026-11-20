// Rules over the Rust sources that remain while the C rewrite replaces them: the
// checker's stage layering (proposals/compiler-stage-layering.md) and Manuscript
// programs held in Rust string literals. Each goes away with the Rust it guards.
import (
	Bytes from "@std/bytes.ms",

	read_text from "./util.ms",
)

// ---- the checker's stage layering ----

// Stage rows, lowest first, as `label: module module`.
STAGES := [
	"syntax: tree facts, types, desugaring: syntax passes types tytable std_ops fxmap",
	"load: bundled sources and the session: bundled stdlib",
	"resolve: declarations, imports, signatures: checker constants prelude_imports",
	"typecheck: bodies, calls, contracts, diagnostics text: hints suggestions contracts exprs stmts calls inference callbacks native native_defaults",
	"analysis: effects, recursion, constant faults, typed HIR: effect_directives effect_reach effects recursion constfaults hir",
	"ownership: moves, borrows, exclusivity: ownership",
	"lints and editor queries (leaves): unused editor", "api: the public surface: api"
]
// Edges that name a later stage, as `from > to: why`. The list only shrinks.
BACK_EDGES := [
	"stdlib > checker: the session checks bundled sources with Checker; revisit after stage 2",
	"checker > ownership: Program holds the one OwnershipFacts value; ends when Program is split from Checker",
	"checker > effect_reach: Program holds the effect diagnostics; ends when Program is split from Checker",
	"checker > constfaults: Program names the constant-fault literal facts; ends when Program is split from Checker",
	"checker > hints: the checker emits hint text; moves with the typecheck diagnostics"
]
// Path-sensitive drop bookkeeping in lowering, as `name count`; a count may only go
// down.
LOWERING_LEDGER := [
	"closed_on_path 18", "scope_done 0", "rest_closers 0", "hidden_closers 0",
	"copy_gaps 5"
]

// The modules of stage row `row`.
fn stage_modules(row: String) List[String]:
	return row.split(": ").last().get_or("").fields()

fn stage_label(row: String) String: row.split(":")[0].clone()

// The stage index of `module`, or -1.
fn stage_of(module: String) Int:
	for at in 0..STAGES.length():
		if stage_modules(STAGES[at]).contains(module): return at
	return -1

fn is_test_file(rest: String) Bool:
	file := rest.split("/").last().get_or(rest)
	return file.ends_with("_tests.rs") or file == "type_keys.rs" or file == "tests.rs"

// The text before the test module.
fn production(text: String) String:
	if at := text.index_of("#[cfg(test)]\nmod "): return text.slice(0, at)
	return text.clone()

fn is_ident(byte: UInt8) Bool:
	return (
		(byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
		or byte == 95
	)

// The modules named by `crate::` paths: the first segment of each path and of each
// top-level member of a `crate::{...}` group.
export fn crate_modules(text: String) List[String]:
	var found = Set[String]()
	var rest = text

	while true:
		at := rest.index_of("crate::").get_or(-1)
		if at < 0: break

		rest = rest.slice(at + 7, rest.length())

		data := rest.as_bytes()

		if rest.starts_with("{"):
			var open = 1
			var end = rest.length()

			for i in 1..rest.length():
				if data.get(i) == 123: open += 1
				if data.get(i) == 125: open -= 1

				if open == 0:
					end = i
					break

			var depth = 0
			var word = ""
			var at_start = true

			for i in 1..end:
				byte := data.get(i)

				if byte == 123:
					depth += 1
				else if byte == 125:
					if depth > 0: depth -= 1
				else if byte == 44:
					if depth == 0: at_start = true

					if not word.is_empty():
						found.add(word.clone())
						word = ""
				else if is_ident(byte):
					if at_start and depth == 0: word += rest.slice(i, i + 1)
				else:
					if not word.is_empty():
						found.add(word.clone())
						word = ""

					if (
						depth == 0
						and byte != 32
						and byte != 10
						and byte != 9
						and byte != 13
					): at_start = false

			if not word.is_empty(): found.add(word.clone())
		else:
			var stop = 0
			while stop < rest.length() and is_ident(data.get(stop)): stop += 1
			found.add(rest.slice(0, stop))

	var out = found.values()
	out.sort()
	return out

fn ledger(files: List[String]) List[String]:
	var counts = Map[String, Int]()

	for path in files:
		if not path.starts_with("crates/ms-lower/src/") or not path.ends_with(".rs"): continue

		text := read_text(path).get_or("")

		for row in LOWERING_LEDGER:
			name := row.split(" ")[0].clone()
			counts.add(name.clone(), counts.get_or(name, 0) + text.count(name))

	var issues = List[String]()

	for row in LOWERING_LEDGER:
		parts := row.split(" ")
		cap := parts[1].parse_int().get_or(0)
		n := counts.get_or(parts[0], 0)
		if n == cap: continue

		verb := if n > cap: "grew" else: "shrank"
		issues.append(
			f"stages.rs: `{parts[0]}` {verb} in crates/ms-lower/src ({n}, recorded {cap}); set its LOWERING_LEDGER cap in tools/repo-check/checks_rust.ms to {n} (it may only go down; proposals/compiler-stage-layering.md step 4b)"
		)

	return issues

fn back_edge_key(row: String) String: row.split(":")[0].clone()

export fn stages(files: List[String]) List[String]:
	var issues = List[String]()
	var seen_edges = Set[String]()
	prefix := "crates/ms-check/src/"

	for path in files:
		rest := path.cut_prefix(prefix).get_or("")
		if (
			rest.is_empty()
			or not path.ends_with(".rs")
			or rest.starts_with("bin/")
			or is_test_file(rest)
		): continue

		module := rest.split("/")[0].replace(".rs", "")
		if module == "lib": continue

		from := stage_of(module)

		if from < 0:
			issues.append(
				f"{path}: module `{module}` has no stage; add it to STAGES in tools/repo-check/checks_rust.ms"
			)
			continue

		text := read_text(path).get_or("")

		for target in crate_modules(production(text)):
			to := stage_of(target)
			if to < 0 or target == module or to <= from: continue

			edge := f"{module} > {target}"
			var known = false
			for row in BACK_EDGES:
				if back_edge_key(row) == edge: known = true

			if known:
				// Clone: moving `edge` here fails to lower (#4660); drop the clone when
				// that is fixed.
				seen_edges.add(edge.clone())
			else:
				issues.append(
					f"{path}: `{module}` ({stage_label(STAGES[from])}) names `{target}` ({stage_label(STAGES[to])}), a later stage; see proposals/compiler-stage-layering.md"
				)

	issues.extend(ledger(files))

	for row in BACK_EDGES:
		if not seen_edges.contains(back_edge_key(row)):
			parts := row.split(": ")
			issues.append(
				f"stages.rs: back-edge `{parts[0].replace(" > ", "` -> `")}` no longer exists; delete its BACK_EDGES row ({parts[1]})"
			)

	return issues

// ---- Manuscript programs belong in `.ms` files, not Rust strings ----

// Existing literals per file, as `path count`; a count here is a ceiling, not a target.
// It only goes down: move the program to a `.ms` file loaded with `include_str!` (or a
// conformance fixture), then lower the count here.
INLINE_BASELINE := [
	"crates/ms-check/tests/list_methods.rs 1", "crates/ms-cli/src/init.rs 1",
	"crates/ms-cli/tests/check_fix.rs 3", "crates/ms-cli/tests/deep_input.rs 3",
	"crates/ms-cli/tests/engine.rs 3", "crates/ms-cli/tests/many_joins.rs 1",
	"crates/ms-cli/tests/min_size_rel.rs 1", "crates/ms-cli/tests/review_diagram.rs 2",
	"crates/ms-cli/tests/search_symbol.rs 1", "crates/ms-driver/tests/load.rs 3",
	"crates/ms-lsp/src/features.rs 1", "crates/ms-lsp/tests/search_symbol.rs 4",
	"crates/ms-lsp/tests/snapshots.rs 1", "crates/ms-tooling/tests/guide_pages.rs 2",
	"crates/ms-tooling/tests/lint_bindings.rs 2",
	"crates/ms-tooling/tests/lint_tasks.rs 4"
]

fn is_program(text: String) Bool:
	lines := text.lines().length()
	return (
		lines >= 4
		and (
			text.contains("export fn ")
			or text.contains("fn main(")
			or (lines >= 6 and text.contains(" from \"@std/"))
		)
	)

// The unescaped contents of every string literal outside comments, as a Rust lexer sees
// them.
fn literals(source: String) List[String]:
	data := source.as_bytes()
	size := data.length()
	var out = List[String]()
	var i = 0

	while i < size:
		c := data.get(i)
		next := if i + 1 < size: data.get(i + 1) else: 0

		if c == 47 and next == 47:
			while i < size and data.get(i) != 10: i += 1
		else if c == 47 and next == 42:
			i += 2
			while i + 1 < size and not (data.get(i) == 42 and data.get(i + 1) == 47): i += 1
			i += 2
		else if c == 39:
			closes := if next == 92: i + 3 else: i + 2

			if closes < size and data.get(closes) == 39:
				i = closes + 1
			else:
				i += 1
		else if (
			c == 114
			and raw_hashes(data, i) >= 0
			and not (i > 0 and is_ident(data.get(i - 1)))
		):
			hashes := raw_hashes(data, i)
			start := i + hashes + 2
			close := "\"" + "#".repeat(hashes)
			var j = start
			while j < size and not source.slice(j, size).starts_with(close): j += 1
			out.append(source.slice(start, if j < size: j else: size))
			i = j + close.length()
		else if c == 34:
			var text = ""
			i += 1

			while i < size and data.get(i) != 34:
				if data.get(i) == 92:
					i += 1
					if i >= size: break

					escaped := data.get(i)

					if escaped == 110:
						text += "\n"
					else if escaped == 10:
						while (
							i < size
							and (
								data.get(i) == 32
								or data.get(i) == 10
								or data.get(i) == 9
								or data.get(i) == 13
							)
						): i += 1
						continue
					else:
						text += source.slice(i, i + 1)
				else:
					text += source.slice(i, i + 1)

				i += 1

			out.append(text)
			i += 1
		else:
			i += 1

	return out

// `r"`, `r#"`, ...: the number of `#` after the `r`, or -1 when this is not a raw string.
fn raw_hashes(data: Bytes, at: Int) Int:
	var j = at + 1
	while j < data.length() and data.get(j) == 35: j += 1
	if j < data.length() and data.get(j) == 34: return j - at - 1

	return -1

// Number of string literals in `source` that look like multi-line Manuscript programs.
export fn inline_programs(source: String) Int:
	var n = 0
	for text in literals(source):
		if is_program(text): n += 1
	return n

export fn inline_source(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if not path.starts_with("crates/") or not path.ends_with(".rs"): continue

		found := inline_programs(read_text(path).get_or(""))
		if found == 0: continue

		var allowed = 0
		for row in INLINE_BASELINE:
			if row.starts_with(path + " "): allowed = (
				row
				.split(" ")[1]
				.parse_int()
				.get_or(0)
			)
		if found > allowed:
			issues.append(
				f"{path}: {found} Rust string literal(s) hold Manuscript programs (allowed {allowed}); move them to .ms files loaded with include_str!, see INLINE_BASELINE in tools/repo-check/checks_rust.ms"
			)

	return issues
