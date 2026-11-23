// Repository invariants that no compiler or test run enforces (`make repo-check`):
//   - every tracked .ms source is formatted (`ms fmt --check`),
//   - nested matches stay out of .ms sources and Markdown code fences (`ms lint --syntax`, MSL107),
//   - .msversion is a calendar version and the VS Code extension carries it,
//   - ci.yml runs on every pull request without path filters and on merge_group.
// `licenses` writes documentation/contributing/dependency-licenses.json from
// src/third_party/c-libs.lock and the bundled notice files; `licenses --check` fails
// when the checked-in file differs. MS names the ms to run. Usage:
//   ms run tools/repo-check.ms [-- licenses [--check]]
import (
	arguments, working_directory from "@std/os/env.ms",
	read_file, write_file from "@std/os/fs.ms",

	capture, env, file_sha256, note, run_program, tool_ms from "./lib.ms",
	stdlib_issues from "./stdlib-rules.ms",
)

// Paths whose sources are not ours to rewrite, or are negative fixtures on purpose.
fn skipped(path: String) Bool:
	return (
		path.starts_with("vendor/")
		or path.starts_with("website/themes/")
		or path.starts_with("tests/conformance/")
		or path.starts_with("tests/removed/")
		or path.starts_with("bench/perf/formatter-flow/")
		or path.starts_with("bench/agent/results/sources/")
		or path.contains("/third_party/")
		or path.contains("/tests/")
	)

// Tracked and untracked-but-not-ignored files, `/`-separated.
fn repository_files() List[String]:
	var files = List[String]()
	listing := capture(
		env("GIT", "git"),
		[
			"ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate"
		],
	)

	for line in listing.split("\n"):
		path := line.trim()
		if path != "": files.append(path)

	return files

fn text_of(path: String) String:
	if bytes := read_file(path).wait(): return (bytes.decode_utf8() or "").replace(
		"\r\n",
		"\n",
	)
	return ""

// ---- formatting and nested matches ----

// Runs `ms <command> <paths...>` in batches so the command line stays short.
fn run_in_batches(ms: String, head: List[String], paths: List[String]) Int:
	var failing = 0
	var at = 0

	while at < paths.length():
		var arguments = head.clone()
		var end = at + 200
		if end > paths.length(): end = paths.length()
		for path in paths.slice(at, end).get():
			arguments.append(path.clone())
		if run_program(ms.clone(), arguments) != 0: failing += 1
		at = end

	return failing

// The files with one of `extensions` that are ours.
fn sources(files: List[String], extensions: List[String]) List[String]:
	var found = List[String]()

	for path in files:
		if skipped(path): continue

		for extension in extensions:
			if path.ends_with(extension): found.append(path.clone())

	return found

// ---- release pins ----

// `YYYY.M.PATCH`: a year, a month 1 to 12 and a patch, no leading zeros, so it is valid semver.
fn plain_number(part: String) Bool:
	if part == "0": return true
	if part == "" or part.starts_with("0"): return false

	for c in part.chars():
		if c < "0" or c > "9": return false
	return true

fn calendar_error(version: String) String:
	parts := version.split(".")
	if parts.length() != 3: return "write YYYY.M.PATCH, for example 2026.11.0"
	if not (
		plain_number(parts[0].clone())
		and plain_number(parts[1].clone())
		and plain_number(parts[2].clone())
	): return "each part is digits with no leading zero, so the version is valid semver"
	if parts[0].length() != 4: return "the year has four digits"

	month := parts[1].parse_int() or 0
	if month < 1 or month > 12: return "the month is 1 to 12"

	return ""

// The first `"version": "..."` value in a package.json text.
fn manifest_version(manifest: String) String:
	marker := "\"version\": \""
	at := manifest.index_of(marker) or (-1)
	if at < 0: return ""

	rest := manifest.slice(at + marker.length(), manifest.length())
	close := rest.index_of("\"") or (-1)
	if close < 0: return ""

	return rest.slice(0, close).clone()

fn release_pins() List[String]:
	var issues = List[String]()
	version := text_of(".msversion").trim()

	if version == "":
		issues.append("cannot read .msversion")
		return issues

	why := calendar_error(version.clone())
	if why != "": issues.append(f".msversion \"{version}\": {why}")

	declared := manifest_version(text_of("extensions/vscode/package.json"))
	if declared != version: issues.append(
		f"extensions/vscode/package.json version {declared} disagrees with .msversion"
	)
	return issues

// ---- workflow triggers ----

fn indent_of(line: String) Int:
	return line.length() - line.trim_start().length()

// The child lines of `key:` at `indent`, up to the next sibling; empty when the key is
// absent.
fn block(lines: List[String], key: String, indent: Int) List[String]?:
	head := f"{" ".repeat(indent)}{key}:"
	var start = -1
	var at = 0

	for line in lines:
		if line.trim_end() == head or line.starts_with(f"{head} "):
			start = at
			break

		at += 1

	if start < 0: return null

	var kept = List[String]()

	for line in lines.slice(start + 1, lines.length()).get():
		if line.trim() != "" and indent_of(line.clone()) <= indent: break

		kept.append(line.clone())

	return kept

// A problem with the workflow's triggers, or empty: it must run on every pull request
// whatever files change, and on the merge queue's combined commit (the ruleset on main
// requires it).
fn trigger_error(text: String) String:
	lines := text.split("\n")
	on := block(lines, "on", 0) or []
	unfiltered := "required checks must run on every pull request without path filters"
	pull := block(on.clone(), "pull_request", 2)

	if pull != null:
		for line in pull:
			if line.trim_start().starts_with("paths"): return unfiltered
	else:
		return unfiltered

	queue := block(on.clone(), "merge_group", 2) or []
	var types = List[String]()

	for line in queue:
		trimmed := line.trim()

		if trimmed.starts_with("types:"): types.append(
			trimmed.slice(6, trimmed.length()).trim()
		)
		else if trimmed.starts_with("- "): types.append(trimmed.clone())

	if types.length() != 1: return "required checks must run on merge_group checks_requested"

	only := types[0].clone()
	if only != "[checks_requested]" and only != "- checks_requested": return "required checks must run on merge_group checks_requested"

	return ""

fn workflow_triggers() List[String]:
	path := ".github/workflows/ci.yml"
	why := trigger_error(text_of(path))
	if why == "": return []

	return [f"{path}: {why}"]

// ---- licenses ----

inventory := "documentation/contributing/dependency-licenses.json"
notice_roots := ["website/themes/hugo-book", "skills"]
notice_names := ["LICENSE", "COPYING", "PATENTS"]

fn quoted(text: String) String:
	return f"\"{text.replace("\\", "\\\\").replace("\"", "\\\"")}\""

// `key=value` field of a c-libs.lock line, or empty.
fn field(line: String, key: String) String:
	for part in line.split(" "):
		if part.starts_with(f"{key}="): return part.slice(
			key.length() + 1,
			part.length(),
		).clone()
	return ""

// The license file a lock line vendors: the entry of `paths=` that names one.
fn license_path(name: String, line: String) String:
	for entry in field(line.clone(), "paths").split(","):
		base := entry.split("/").last() or ""
		for stem in ["LICENSE", "LICENCE", "COPYING"]:
			if base.starts_with(stem): return f"src/third_party/{name}/{entry}"

	return ""

fn notices_under(files: List[String]) List[String]:
	var found = List[String]()

	for path in files:
		for root in notice_roots:
			if not path.starts_with(f"{root}/"): continue

			base := path.split("/").last() or ""
			if notice_names.contains(base): found.append(path.clone())

	return found

fn libraries(lock: String) List[String]:
	var entries = List[String]()

	for line in lock.split("\n"):
		if line == "" or line.starts_with("#"): continue

		name := line.split(" ")[0].clone()
		path := license_path(name.clone(), line.clone())
		var digest = ""
		if path != "": digest = file_sha256(path.clone())

		version := quoted(field(line.clone(), "version"))
		entries.append(
			f"    \{\"name\": {quoted(name)}, \"version\": {version}, \"license\": {quoted(path)}, \"sha256\": {quoted(digest)}\}"
		)

	return entries

fn inventory_text(files: List[String]) String:
	var notices = List[String]()

	for path in notices_under(files):
		digest := quoted(file_sha256(path.clone()))
		notices.append(
			f"    \{\"path\": {quoted(path.clone())}, \"sha256\": {digest}\}"
		)

	notices.sort()

	separator := ",\n"
	known := libraries(text_of("src/third_party/c-libs.lock")).join(separator.clone())
	listed := notices.join(separator)
	return f"\{\n  \"libraries\": [\n{known}\n  ],\n  \"notices\": [\n{listed}\n  ]\n\}\n"

fn licenses(check: Bool) Int:
	files := repository_files()

	if files.is_empty():
		note(
			"git listed no files; run from the repository root with git on PATH, or name it in GIT"
		)
		return 1

	wanted := inventory_text(files)

	if check:
		if text_of(inventory) == wanted: return 0

		note("dependency licenses changed; run make licenses")
		return 1

	write_file(inventory, wanted, replace: true).wait().get()
	return 0

// ---- main ----

fn main() Int:
	words := arguments()
	if words.length() > 0 and words[0] == "licenses": return licenses(
		words.contains("--check")
	)

	root := working_directory().get()
	ms := tool_ms(root)
	files := repository_files()

	if files.is_empty():
		note(
			"git listed no files; run from the repository root with git on PATH, or name it in GIT"
		)
		return 1

	var failing = 0
	failing += run_in_batches(
		ms.clone(),
		["fmt", "--check"],
		sources(files.clone(), [".ms"]),
	)
	failing += run_in_batches(
		ms.clone(),
		["lint", "--syntax"],
		sources(files, [".ms", ".md"]),
	)

	var issues = release_pins()
	issues = issues.concat(stdlib_issues(files.clone()))
	issues = issues.concat(workflow_triggers())
	for issue in issues:
		note(issue.clone())
	if failing != 0 or issues.length() != 0: return 1

	print("Formatting, nested matches, release pins and workflow triggers agree.")
	return 0
