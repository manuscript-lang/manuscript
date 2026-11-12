// Repository invariants that read text, not syntax trees: release pins, workflow
// triggers, the unsafe boundary, thread affinity, portability, crate layering and the
// internal extern surface. The rules that parse Manuscript (nested matches, formatting,
// stream names, impl adjacency, optional defaults, inline sources, stages) stay in the
// `repo-check` Rust binary, which reads the compiler's syntax tree.
// Run from the repository root: `ms run tools/repo_check.ms`.
import (
	parse from "@std/data/json.ms",
	read_file, stat from "@std/os/fs.ms",

	capture, note from "./lib.ms",
)

// Reads a UTF-8 text file; empty when it cannot be read.
fn read_text(path: String) String:
	if data := read_file(path).wait(): return data.decode_utf8().get("")
	return ""

type PackageVersion:
	version: String = ""

// Vendored code and frozen conformance inputs are not ours to rewrite.
fn skipped(path: String) Bool:
	return (
		path.starts_with("vendor/")
		or path.starts_with("website/themes/")
		or path.starts_with("tests/conformance/fixtures/")
	)

// Tracked and untracked-but-not-ignored files that still exist, `/`-separated.
fn tracked_files() List[String]:
	listing := capture(
		"git",
		[
			"ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate",
			"-z"
		],
	)
	var found = List[String]()

	for path in listing.split("\u{0}"):
		if path.is_empty(): continue

		if info := stat(path):
			if info.is_file(): found.append(path.clone())

	return found

fn is_word_char(scalar: Int) Bool:
	return (
		(scalar >= 48 and scalar <= 57)
		or (scalar >= 65 and scalar <= 90)
		or (scalar >= 97 and scalar <= 122)
		or scalar == 95
		or scalar > 127
	)

// Whether `word` occurs in `text` bounded by non-identifier characters.
export fn contains_word(text: String, word: String) Bool:
	var from = 0

	while true:
		rest := text.drop(from)
		at := rest.index_of(word).get(-1)
		if at < 0: return false

		start := from + at
		stop := start + word.scalar_length()
		before_ok := start == 0 or not is_word_char(text.scalar_at(start - 1, 0))
		after_ok := (
			stop >= text.scalar_length()
			or not is_word_char(text.scalar_at(stop, 0))
		)
		if before_ok and after_ok: return true

		from = start + 1

	return false

// `.msversion` and the VS Code extension manifest name the same version.
fn extension_version() List[String]:
	release := read_text(".msversion").trim()
	manifest := read_text("extensions/vscode/package.json")
	parsed := parse[PackageVersion](manifest)
	if parsed.is_error(): return [
		"cannot read .msversion or extensions/vscode/package.json"
	]

	version := parsed.get().version
	if version == release: return []

	return [
		"extensions/vscode/package.json version {version} disagrees with .msversion"
	]

// Lines of the child block of `key:` at `indent`, stopping at the next sibling.
fn block(lines: List[String], key: String, indent: Int) List[String]?:
	head := "{" ".repeat(indent).get("")}{key}:"
	var start = -1

	for index in 0..lines.length():
		line := lines[index].trim_end()

		if line == head or lines[index].starts_with("{head} "):
			start = index
			break

	if start < 0: return none

	var found = List[String]()

	for index in (start + 1)..lines.length():
		line := lines[index]

		if line.trim().is_empty() or leading_spaces(line) > indent:
			found.append(line.clone())
		else:
			break

	return found

fn leading_spaces(line: String) Int:
	return line.length() - line.trim_start().length()

// The CI workflow runs on every pull request, whatever files change, and on the merge
// queue's combined commit: the ruleset on `main` requires its `Platform checks` job.
fn workflow_triggers() List[String]:
	path := ".github/workflows/cicd.yml"
	return trigger_issues(path, read_text(path))

export fn trigger_issues(path: String, text: String) List[String]:
	lines := text.lines()
	on := block(lines, "on", 0).get([])

	// `pull_request:` may carry an inline value; any child key is a filter.
	var filtered = true

	if pull := block(on, "pull_request", 2):
		filtered = false
		for line in pull:
			if line.trim_start().starts_with("paths"): filtered = true

	if filtered:
		return [
			"{path}: required checks must run on every pull request without path filters"
		]

	queue := block(on, "merge_group", 2).get([])
	var types = List[String]()

	for line in queue:
		entry := line.trim()
		if entry.starts_with("types:") or entry.starts_with("- "):
			types.append(entry.replace_first("types:", "").trim())

	if types == ["[checks_requested]"] or types == ["- checks_requested"]: return []

	return ["{path}: required checks must run on merge_group checks_requested"]

// Only listed Rust locations may use `unsafe` or lift the workspace `unsafe_code` lint.
UNSAFE_ALLOWED := [
	"crates/ms-rt/", "crates/ms-std-", "crates/ms-rt-abi/", "crates/ms-rt-hot/",
	"crates/ms-native/src/entry.rs", "crates/ms-native/tests/std_natives.rs",
	"crates/ms-cli/src/process.rs", "crates/ms-syntax/src/symbol.rs",
	"crates/ms-lsp/src/server.rs", "crates/ms-cli/tests/terminal.rs",
	"bench/perf/binding-flags/main.rs", "bench/perf/binding-flags/storage.rs"
]

export fn unsafe_allowed(path: String) Bool:
	for prefix in UNSAFE_ALLOWED:
		if prefix.ends_with("/") or prefix.ends_with("-"):
			if path.starts_with(prefix): return true
		else if path == prefix: return true

	return false

// The first use of the keyword in code, or a lint attribute lifting the ban.
export fn unsafe_use(source: String) String?:
	keyword := "uns" + "afe"

	for lint in ["allow", "forbid"]:
		needle := "{lint}({keyword}_code)"
		if source.contains(needle): return needle

	var from = 0

	while true:
		at := source.drop(from).index_of(keyword).get(-1)
		if at < 0: return none

		start := from + at
		stop := start + keyword.scalar_length()
		from = stop
		if start > 0 and is_word_char(source.scalar_at(start - 1, 0)): continue

		rest := source.drop(stop).trim_start()
		if rest.starts_with("\{"): return "{keyword} \{"

		for next in ["fn", "impl", "trait", "extern"]:
			if (
				rest.starts_with(next)
				and not is_word_char(
					rest.scalar_at(next.scalar_length(), 0)
				)
			):
				return "{keyword} {next}"

	return none

fn unsafe_boundary(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		in_scope := (
			path.ends_with(".rs")
			and (path.starts_with("crates/") or path.starts_with("bench/"))
		)
		if not in_scope or unsafe_allowed(path): continue

		if found := unsafe_use(read_text(path)):
			issues.append(
				"{path} uses unsafe ({found}) outside the allowed Rust modules; see UNSAFE_ALLOWED in tools/repo_check.ms"
			)

	return issues

// A standard-library crate does not add `Rc`, `Weak` or `RefCell`: a promise may run on
// another thread. `thread-affinity-allowed.txt` lists `path count` for files that still
// use them; a count may only go down.
AFFINITY_LIST := "crates/ms-repo-check/thread-affinity-allowed.txt"

export fn uses_thread_unsafe(line: String) Bool:
	code := line.split("//").get(0, "")
	return (
		contains_word(code, "Rc")
		or contains_word(code, "RefCell")
		or code.contains("rc::Weak")
		or (code.contains("Weak") and code.contains("rc"))
	)

fn thread_affinity(files: List[String]) List[String]:
	var allowed = Map[String, Int]()

	for raw in read_text(AFFINITY_LIST).lines():
		line := raw.trim()
		if line.is_empty() or line.starts_with("//"): continue

		at := line.last_index_of(" ").get(-1)
		if at < 0: continue

		if count := line.drop(at + 1).parse_int(): allowed.add(line.take(at), count)

	var issues = List[String]()
	var seen = Set[String]()

	for path in files:
		if not (
			path.starts_with("crates/ms-std-")
			and path.ends_with(".rs")
			and path.contains("/src/")
		): continue

		var count = 0
		for line in read_text(path).lines():
			if uses_thread_unsafe(line): count += 1

		limit := allowed.get(path).get(0)
		if count > 0: seen.add(path.clone())

		if count > limit:
			issues.append(
				"{path}: {count} lines use Rc, Weak or RefCell (allowed {limit}); a promise may run on another thread, so use Arc, atomics or a lock, or wrap a deliberately thread-bound handle in `Bound`"
			)
		else if count < limit:
			hint := if count == 0: " (delete it)" else: ""
			issues.append(
				"{AFFINITY_LIST}: `{path}` now has {count} such lines; lower the entry from {limit}{hint}"
			)

	for entry in allowed.entries():
		if not seen.contains(entry.key) and not files.contains(entry.key):
			issues.append(
				"{AFFINITY_LIST}: `{entry.key}` no longer exists; delete the line"
			)
	return issues

// Every `extern fn` under `stdlib/internal/` is named by another standard-library file:
// a native nobody imports costs a symbol, an ABI entry and tests for nothing.
export fn extern_names(text: String) List[String]:
	var names = List[String]()

	for raw in text.lines():
		var line = raw.trim_start()
		if line.starts_with("export "): line = line.drop(7)
		if not line.starts_with("extern fn "): continue

		rest := line.drop(10)
		var length = 0

		for scalar in rest.scalar_values():
			if not is_word_char(scalar): break

			length += 1

		if length > 0 and length < rest.scalar_length(): names.append(rest.take(length))

	return names

fn internal_externs(files: List[String]) List[String]:
	var sources = Map[String, String]()
	for path in files:
		if path.starts_with("stdlib/") and path.ends_with(".ms"): sources.add(
			path.clone(),
			read_text(path),
		)

	var issues = List[String]()

	for entry in sources.entries():
		if not entry.key.starts_with("stdlib/internal/"): continue

		for name in extern_names(entry.value):
			var used = false
			for other in sources.entries():
				if other.key != entry.key and contains_word(other.value, name): used = true
			if not used:
				issues.append(
					"{entry.key}: `extern fn {name}` is not used by any other standard-library file; delete it and its Rust side"
				)

	return issues

// Paths and line endings that must read the same on Linux, macOS and Windows.
// Windows device names: a file with one of these stems cannot be created there.
RESERVED := [
	"con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
	"com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
	"lpt9"
]
// Extensions whose bytes tests compare, so they must be LF-only in every checkout.
TEXT := [
	"ms", "toml", "json", "md", "rs", "sh", "yml", "yaml", "txt", "src", "py", "html",
	"css"
]

// `.gitattributes` keeps source and corpora LF on Windows checkouts.
fn attributes() List[String]:
	lines := read_text(".gitattributes").lines().map(fn line: line.trim())
	if lines.is_empty(): return [".gitattributes: missing"]

	var issues = List[String]()
	for rule in ["*.ms text eol=lf", "*.toml text eol=lf", "* text=auto eol=lf"]:
		if not lines.contains(rule):
			issues.append(".gitattributes: missing the rule `{rule}`")
	return issues

// Tracked paths must be creatable and distinct on case-insensitive, reserved-name-aware
// file systems.
export fn path_names(files: List[String]) List[String]:
	var issues = List[String]()
	var folded = Map[String, String]()

	for path in files:
		key := path.lower()

		if other := folded.get(key):
			if other != path: issues.append("{path}: differs from {other} only by case")
		else:
			folded.add(key, path.clone())

		for part in path.split("/"):
			stem := part.split(".").get(0, part).lower()
			if RESERVED.contains(stem): issues.append(
				"{path}: `{part}` is a reserved name on Windows"
			)
			if part.ends_with(".") or part.ends_with(" "):
				issues.append("{path}: `{part}` ends in a dot or space")
			if part.contains_any("<>:\"\\|?*"):
				issues.append("{path}: `{part}` has a character Windows rejects")

	return issues

// No carriage returns in text the tests compare byte for byte.
fn line_endings(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if skipped(path) or not path.contains("."): continue

		extension := path.split(".").last().get("")
		if TEXT.contains(extension) and read_text(path).contains("\r"):
			issues.append(
				"{path}: contains a carriage return; store it with LF line endings"
			)

	return issues

// Standard-library import specifiers are `@std/…` or `./…` with forward slashes.
fn stdlib_imports(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if not (path.starts_with("stdlib/") and path.ends_with(".ms")): continue

		var number = 0

		for raw in read_text(path).lines():
			number += 1

			line := raw.trim_start()
			if not (line.starts_with("from \"") or line.starts_with("import \"")): continue

			spec := line.split("\"").get(1, "")
			local := spec.starts_with("./") or spec.starts_with("../")
			if spec.contains("\\") or not (spec.starts_with("@std/") or local):
				issues.append(
					"{path}:{number}: import `{spec}` is not a forward-slash `@std/` or relative path"
				)

	return issues

fn portability(files: List[String]) List[String]:
	var issues = attributes()
	issues.extend(path_names(files))
	issues.extend(line_endings(files))
	issues.extend(stdlib_imports(files))
	return issues

// Crate layering. Allowed normal dependencies on other workspace crates, per compiler
// or tool crate. The runtime (`ms-rt-abi`, `ms-rt-hot`, `ms-rt`, `ms-std-*`,
// `ms-native`) is a separate world the compiler meets only through `ms-rt-abi`.
// Widening a row needs a reason beside it, in the same change. `ms-decimal` is pure
// arithmetic both worlds use.
COMPILER_AND_TOOLS := {
	"ms-syntax": [],
	"ms-json": [],
	"ms-mir": [],
	"ms-decimal": [],
	"ms-check": ["ms-syntax"],
	"ms-lower": ["ms-check", "ms-mir", "ms-rt-abi", "ms-decimal"],
	"ms-clif": ["ms-mir", "ms-rt-abi"],
	"ms-build": ["ms-check", "ms-clif", "ms-lower", "ms-mir"],
	"ms-driver": ["ms-check", "ms-syntax"],
	"ms-tooling": ["ms-check", "ms-json", "ms-syntax"],
	"ms-lsp": ["ms-check", "ms-driver", "ms-json", "ms-syntax", "ms-tooling"],
	"ms-cli": [
		"ms-build", "ms-check", "ms-driver", "ms-json", "ms-lsp", "ms-mir", "ms-rt-abi",
		"ms-syntax", "ms-tooling"
	]
}
RUNTIME := ["ms-rt-abi", "ms-rt-hot", "ms-rt", "ms-std-", "ms-native"]

fn is_runtime(name: String) Bool:
	for prefix in RUNTIME:
		if name.starts_with(prefix): return true
	return false

export fn layering_violation(name: String, dep: String) String?:
	if is_runtime(name):
		if dep != "ms-decimal" and COMPILER_AND_TOOLS.contains(dep):
			return "a runtime crate must not depend on a compiler crate"
		return none

	if allowed := COMPILER_AND_TOOLS.get(name):
		if not allowed.contains(dep): return "not in this crate's allowed dependencies"
	return none

// Workspace (`ms-*`) crates named in the `[dependencies]` table only.
export fn normal_dependencies(manifest: String) List[String]:
	var in_table = false
	var found = List[String]()

	for line in manifest.lines():
		if line.starts_with("["):
			in_table = line.trim() == "[dependencies]"
			continue

		key := line.split_after("=").get(0, "").split(" ").get(0, "").split(".").get(
			0,
			"",
		).replace("=", "")
		if in_table and key.starts_with("ms-"): found.append(key)

	return found

// Editor queries (`editor.rs`) sit on top of the checker; the checker never calls back
// into them. Only the public `api`, the module list and tests may name the module.
export fn allowed_to_name_editor(path: String) Bool:
	file := path.split("/").last().get(path)
	return file == "api.rs" or file == "editor.rs" or file.ends_with("_tests.rs")

fn layering(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if path.starts_with("crates/") and path.ends_with("/Cargo.toml"):
			manifest := read_text(path)
			var name = ""

			for line in manifest.lines():
				if line.starts_with("name = "):
					name = line.split("\"").get(1, "")
					break

			if name.is_empty(): continue

			for dep in normal_dependencies(manifest):
				if why := layering_violation(name, dep):
					issues.append(
						"{path}: {name} -> {dep}: {why}; see tools/repo_check.ms"
					)

		in_checker := path.starts_with("crates/ms-check/src/") and path.ends_with(".rs")
		if (
			in_checker
			and not allowed_to_name_editor(path)
			and read_text(path).contains("crate::editor")
		):
			issues.append(
				"{path}: checker code must not depend on `crate::editor` (editor queries are a leaf); see tools/repo_check.ms"
			)

	return issues

fn run_checks() List[String]:
	files := tracked_files()
	if files.is_empty(): return [
		"git ls-files returned no files; run from the repository root with git available"
	]

	var issues = List[String]()
	issues.extend(extension_version())
	issues.extend(workflow_triggers())
	issues.extend(unsafe_boundary(files))
	issues.extend(thread_affinity(files))
	issues.extend(internal_externs(files))
	issues.extend(portability(files))
	issues.extend(layering(files))
	return issues

// ms: allow_effect std.console.write
fn main() Int:
	issues := run_checks()

	if issues.is_empty():
		print(
			"Release pins, triggers, unsafe boundary, thread affinity, internal externs, portability and crate layering agree."
		)
		return 0

	note("repository invariants:\n- {issues.sorted().join("\n- ")}")
	return 1
