// Repository checks that read file text only: paths, line endings, the Rust-source
// rules (unsafe boundary, cancel by return, timed waits, thread affinity, crate
// layering) and the standard library's extern declarations.
import (
	code_of,
	contains_word,
	has_carriage_return,
	list_lines,
	read_text,
	skipped,
	words
) from "./util.ms"

// ---- portability: paths and line endings that must read the same on every platform ----

// Windows device names; a file with one of these stems cannot be created there.
RESERVED := [
	"con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
	"com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
	"lpt9"
]
// Extensions whose bytes tests compare, so they must be LF-only in every checkout.
TEXT_EXTENSIONS := [
	"ms", "toml", "json", "md", "rs", "sh", "yml", "yaml", "txt", "src", "py", "html",
	"css", "c", "h"
]

export fn portability(files: List[String]) List[String]:
	var issues = attributes()
	issues.extend(path_names(files))
	issues.extend(line_endings(files))
	issues.extend(stdlib_imports(files))
	return issues

// `.gitattributes` must keep source and corpora LF on Windows checkouts.
fn attributes() List[String]:
	text := read_text(".gitattributes").get_or("")
	if text.is_empty(): return [".gitattributes: missing"]

	var issues = List[String]()
	lines := text.lines().map(fn line: line.trim())
	for rule in ["*.ms text eol=lf", "*.toml text eol=lf", "* text=auto eol=lf"]:
		if not lines.contains(rule): issues.append(
			f".gitattributes: missing the rule `{rule}`"
		)
	return issues

// Tracked paths must be creatable and distinct on case-insensitive, reserved-name-aware
// file systems.
export fn path_names(files: List[String]) List[String]:
	var issues = List[String]()
	var folded = Map[String, String]()

	for path in files:
		key := path.lower()

		if other := folded.get(key):
			if other != path: issues.append(
				f"{path}: differs from {other} only by case"
			)
		else:
			folded.add(key, path.clone())

		for part in path.split("/"):
			stem := part.split(".")[0].lower()
			if RESERVED.contains(stem):
				issues.append(f"{path}: `{part}` is a reserved name on Windows")
			if part.ends_with(".") or part.ends_with(" "):
				issues.append(f"{path}: `{part}` ends in a dot or space")
			if part.contains_any("<>:\"\\|?*"):
				issues.append(f"{path}: `{part}` has a character Windows rejects")

	return issues

fn line_endings(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if skipped(path) or not path.contains("."): continue

		extension := path.split(".").last().get_or("")
		if not TEXT_EXTENSIONS.contains(extension): continue

		if has_carriage_return(path):
			issues.append(
				f"{path}: contains a carriage return; store it with LF line endings"
			)

	return issues

// Standard-library import specifiers are `@std/…` or `./…` with forward slashes.
fn stdlib_imports(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if not path.starts_with("stdlib/") or not path.ends_with(".ms"): continue

		text := read_text(path).get_or("")
		var number = 0

		for raw in text.lines():
			number += 1

			line := raw.trim_start()
			if not (line.starts_with("from \"") or line.starts_with("import \"")): continue

			parts := line.split("\"")
			spec := parts.get_or(1, "")
			local := spec.starts_with("./") or spec.starts_with("../")
			if spec.contains("\\") or not (spec.starts_with("@std/") or local):
				issues.append(
					f"{path}:{number}: import `{spec}` is not a forward-slash `@std/` or relative path"
				)

	return issues

// ---- the internal-surface rule: every `extern fn` under stdlib/internal is used elsewhere ----

export fn internal_externs(files: List[String]) List[String]:
	var sources = Map[String, String]()
	for path in files:
		if path.starts_with("stdlib/") and path.ends_with(".ms"):
			if text := read_text(path): sources.add(path.clone(), text)

	var issues = List[String]()

	for path in sources.keys():
		if not path.starts_with("stdlib/internal/"): continue

		for name in extern_names(sources.get_or(path, "")):
			var used = false

			for other in sources.keys():
				if other != path and contains_word(sources.get_or(other, ""), name):
					used = true
					break

			if not used:
				issues.append(
					f"{path}: `extern fn {name}` is not used by any other standard-library file; delete it and its native side"
				)

	return issues

// Names declared by `extern fn name` (optionally `export extern fn`), generic or not.
export fn extern_names(text: String) List[String]:
	var found = List[String]()

	for raw in text.lines():
		line := raw.trim_start()
		rest := line.cut_prefix("export ").get_or(line)
		after := rest.cut_prefix("extern fn ").get_or("")
		if after.is_empty(): continue

		name := words(after).first().get_or("")
		if not name.is_empty() and after.starts_with(name): found.append(name)

	return found

// ---- Rust-source rules ----

// Only listed Rust locations may use `unsafe` or lift the workspace `unsafe_code` lint.
UNSAFE_ALLOWED := [
	"crates/ms-rt/", "crates/ms-std-", "crates/ms-rt-abi/",
	"crates/ms-native/src/heap.rs", "crates/ms-native/tests/std_natives.rs",
	"crates/ms-cli/src/process.rs", "crates/ms-syntax/src/symbol.rs",
	"crates/ms-lsp/src/server.rs", "crates/ms-cli/tests/shutdown_windows.rs",
	"crates/ms-cli/tests/terminal.rs", "bench/perf/binding-flags/main.rs",
	"bench/perf/binding-flags/storage.rs", "crates/ms-build/src/c_backend.rs"
]

fn unsafe_allowed(path: String) Bool:
	for entry in UNSAFE_ALLOWED:
		if entry.ends_with(".rs"):
			if path == entry: return true
		else if path.starts_with(entry):
			return true

	return false

export fn unsafe_boundary(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if not path.ends_with(".rs"): continue
		if not (path.starts_with("crates/") or path.starts_with("bench/")): continue
		if unsafe_allowed(path): continue

		text := read_text(path).get_or("")
		found := unsafe_use(text)
		if not found.is_empty():
			issues.append(
				f"{path} uses unsafe ({found}) outside the allowed Rust modules; see UNSAFE_ALLOWED in tools/repo-check/checks_text.ms"
			)

	return issues

// The first use of the keyword in code, or a lint attribute lifting the ban; "" when
// none.
export fn unsafe_use(source: String) String:
	keyword := "uns" + "afe"

	for lint in ["allow", "forbid"]:
		needle := f"{lint}({keyword}_code)"
		if source.contains(needle): return needle

	data := source.as_bytes()
	var from = 0

	while from < source.length():
		rest := source.slice(from, source.length())
		at := rest.index_of(keyword).get_or(-1)
		if at < 0: break

		start := from + at
		end := start + keyword.length()
		from = end
		if start > 0 and is_word(data.get(start - 1)): continue

		after := source.slice(end, source.length()).trim_start()
		var opens = after.starts_with("{")
		for word in ["fn", "impl", "trait", "extern"]:
			if tail := after.cut_prefix(word):
				if tail.is_empty() or not is_word(tail.as_bytes().get(0)): opens = true
		if opens: return source.slice(start, end)

	return ""

fn is_word(byte: UInt8) Bool:
	return (
		(byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
		or byte == 95
	)

// Cancel by return: a native never ends a cancelled call with the runtime's jump. The
// jump stays only where nothing sits above it.
CANCEL_ALLOWED := ["crates/ms-rt/src/fault.rs", "crates/ms-rt/src/start.rs"]

export fn cancel_jumps(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		in_scope := (
			path.ends_with(".rs")
			and path.contains("/src/")
			and (
				path.starts_with("crates/ms-rt/")
				or path.starts_with("crates/ms-std-")
			)
		)
		if not in_scope or CANCEL_ALLOWED.contains(path): continue

		var number = 0

		for line in (read_text(path).get_or("")).lines():
			number += 1
			if code_of(line).contains("msrt_cancelled"):
				issues.append(
					f"{path}:{number}: a native must not jump on cancel; call `cancel_return()` and return a zero result"
				)

	return issues

// The timed-wait rule: a wait that wakes on a period to see whether something changed
// makes the runtime fragile. New calls that sleep or wait with a timeout need an entry,
// with the reason, in `timed-waits-allowed.txt`. A file may not exceed its count, and a
// count that no longer matches fails so the list only shrinks.
TIMED_ALLOWED := "tools/repo-check/timed-waits-allowed.txt"

fn waits_on_time(line: String) Bool:
	code := code_of(line)
	for needle in ["sleep(", "park_timeout(", "recv_timeout(", "wait_timeout"]:
		if code.contains(needle): return true
	return false

export fn timed_waits(files: List[String]) List[String]:
	var allowed = Map[String, Int]()
	var issues = List[String]()

	for line in list_lines(read_text(TIMED_ALLOWED).get_or("")):
		parts := line.split(" ")
		count := parts.get_or(1, "").parse_int().get_or(-1)
		reason := parts.slice(2, parts.length()).get_or([]).join(" ").trim()

		if count >= 0 and not reason.is_empty():
			allowed.add(parts[0].clone(), count)
		else:
			issues.append(f"{TIMED_ALLOWED}: `{line}` needs `path count reason`")

	for path in files:
		if not path.starts_with("crates/") or not path.ends_with(".rs"): continue

		var count = 0
		for line in (read_text(path).get_or("")).lines():
			if waits_on_time(line): count += 1

		limit := allowed.get_or(path, 0)

		if count > limit:
			issues.append(
				f"{path}: {count} calls sleep or wait with a timeout (allowed {limit}); wait on the event instead, or if this is a deadline with a meaning add the file to {TIMED_ALLOWED} with the reason"
			)
		else if count < limit:
			hint := if count == 0: " (delete it)" else: ""
			issues.append(
				f"{TIMED_ALLOWED}: `{path}` now has {count} such calls; lower the entry from {limit}{hint}"
			)

	for path in allowed.keys():
		if not files.contains(path):
			issues.append(
				f"{TIMED_ALLOWED}: `{path}` no longer exists; delete the line"
			)
	return issues

// The thread-affinity rule: `promise(fn:)` may run its entry on any scheduler thread,
// so a native handle built on `Rc`, `Weak` or `RefCell` races when a promise captures
// it. A file in
// `thread-affinity-allowed.txt` (`path count`) may not exceed its count, and a count that no
// longer matches fails so the list only shrinks.
AFFINITY_ALLOWED := "tools/repo-check/thread-affinity-allowed.txt"

fn uses_thread_unsafe(line: String) Bool:
	code := code_of(line)
	for word in words(code):
		if word == "Rc" or word == "RefCell": return true
	return code.contains("rc::Weak") or (code.contains("Weak") and code.contains("rc"))

export fn thread_affinity(files: List[String]) List[String]:
	var allowed = Map[String, Int]()
	for line in list_lines(read_text(AFFINITY_ALLOWED).get_or("")):
		if parts := line.rsplit_once(" "):
			if count := parts.after.parse_int(): allowed.add(
				parts.before.clone(),
				count,
			)

	var issues = List[String]()
	var seen = Set[String]()

	for path in files:
		if not path.starts_with("crates/ms-std-") or not path.ends_with(".rs"): continue
		if not path.contains("/src/"): continue

		var count = 0
		for line in (read_text(path).get_or("")).lines():
			if uses_thread_unsafe(line): count += 1

		limit := allowed.get_or(path, 0)
		if count > 0: seen.add(path.clone())

		if count > limit:
			issues.append(
				f"{path}: {count} lines use Rc, Weak or RefCell (allowed {limit}); a promise may run on another thread, so use Arc, atomics or a lock, or wrap a deliberately thread-bound handle in `Bound`"
			)
		else if count < limit:
			hint := if count == 0: " (delete it)" else: ""
			issues.append(
				f"{AFFINITY_ALLOWED}: `{path}` now has {count} such lines; lower the entry from {limit}{hint}"
			)

	for path in allowed.keys():
		if not seen.contains(path) and not files.contains(path):
			issues.append(
				f"{AFFINITY_ALLOWED}: `{path}` no longer exists; delete the line"
			)
	return issues

// ---- crate layering ----

// Allowed normal dependencies on other workspace crates, per compiler or tool crate, as
// `crate: dependency dependency`. Widening a row needs a reason beside it, in the same change.
LAYERS := [
	"ms-syntax:", "ms-json:", "ms-mir: ms-rt-abi", "ms-check: ms-syntax",
	"ms-lower: ms-check ms-mir ms-rt-abi", "ms-build: ms-check ms-lower ms-mir",
	"ms-driver: ms-check ms-syntax", "ms-tooling: ms-check ms-driver ms-json ms-syntax",
	"ms-lsp: ms-check ms-driver ms-json ms-syntax ms-tooling",
	"ms-cli: ms-build ms-check ms-driver ms-json ms-lsp ms-mir ms-rt-abi ms-syntax ms-tooling"
]

// The runtime is a separate world: it never depends on a compiler crate, and a compiler
// crate never depends on a runtime crate other than `ms-rt-abi`.
fn is_runtime(name: String) Bool:
	for prefix in ["ms-rt-abi", "ms-rt", "ms-std-", "ms-native"]:
		if name.starts_with(prefix): return true
	return false

fn layer_row(name: String) List[String]?:
	for row in LAYERS:
		if parts := row.split_once(":"):
			if parts.before == name: return parts.after.fields()
	return none

fn is_compiler_crate(name: String) Bool:
	return layer_row(name).is_some()

// Why `name` may not depend on `dep`, or "".
export fn layering_violation(name: String, dep: String) String:
	if is_runtime(name):
		if is_compiler_crate(dep): return "a runtime crate must not depend on a compiler crate"
		return ""

	if allowed := layer_row(name):
		if not allowed.contains(dep): return "not in this crate's allowed dependencies"
	return ""

// Workspace (`ms-*`) crates named in the `[dependencies]` table only.
export fn normal_dependencies(manifest: String) List[String]:
	var in_table = false
	var found = List[String]()

	for line in manifest.lines():
		if line.starts_with("["):
			in_table = line.trim() == "[dependencies]"
			continue

		key := line.fields_by(fn c: c == "=" or c == "." or c == " ").first().get_or("")
		if in_table and key.starts_with("ms-"): found.append(key)

	return found

fn package_name(manifest: String) String:
	for line in manifest.lines():
		if line.starts_with("name = "): return line.split("\"").get_or(1, "")
	return ""

// Editor queries sit on top of the checker; the checker never calls back into them.
fn allowed_to_name_editor(path: String) Bool:
	file := path.split("/").last().get_or(path)
	return file == "api.rs" or file == "editor.rs" or file.ends_with("_tests.rs")

export fn layering(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if path.starts_with("crates/") and path.ends_with("/Cargo.toml"):
			manifest := read_text(path).get_or("")
			name := package_name(manifest)
			if name.is_empty(): continue

			for dep in normal_dependencies(manifest):
				why := layering_violation(name, dep)
				if not why.is_empty():
					issues.append(
						f"{path}: {name} -> {dep}: {why}; see LAYERS in tools/repo-check/checks_text.ms"
					)
		else if (
			path.starts_with("crates/ms-check/src/")
			and path.ends_with(".rs")
			and not allowed_to_name_editor(path)
		):
			if read_text(path).get_or("").contains("crate::editor"):
				issues.append(
					f"{path}: checker code must not depend on `crate::editor` (editor queries are a leaf); see tools/repo-check/checks_text.ms"
				)

	return issues
