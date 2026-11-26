// ms: allow_effect std.console.write
// ms: allow_effect std.env.read
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run
// ms: allow_effect std.system.read

// `conform harvest`: turns the repository's Manuscript sources and the ```manuscript fences of the
// documentation into corpus fixtures. Each candidate is classified by asking the ms
// under test to check it: parse errors become `parse` fixtures, type errors `check`
// fixtures, clean programs with
// `main` `run` fixtures and clean programs with `test` blocks `test` fixtures. Expectations are
// recorded afterwards with `ms run tools/conform-run.ms -- --record --prune`.
import (
	Promise, promise from "@std/concurrency/promise.ms",
	JsonValue, parse from "@std/data/json.ms",
	CopyOptions,
	GlobOptions,
	copy,
	create_directory,
	glob,
	remove,
	temporary,
	write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",
	seconds from "@std/time.ms",

	tool_ms from "../lib.ms",
	Args, has, number, one from "./args.ms",
	Meta, parent_length, read_text, render_meta, text_of from "./corpus.ms",
	hostile, slugify, sorted_unique, tags_for from "./tags.ms",
)

SKIP_DIRS List[String] := [
	"vendor", "toolchain", "target", "node_modules", "website", "dist"
]

// What can be fixtured: a single source, or a project directory (has `ms.toml`).
type Candidate {
	// Where it came from, recorded in the fixture header.
	origin String
	// Directory (`snippets`, `e2e`, ...) and slug that make the fixture id.
	category, slug String
	is_project Bool
	text, dir String
}

// What `ms check` said about a candidate.
type Verdict {
	parse_errors, type_errors Bool
	unusable String
}

fn skipped(path String) Bool {
	for part in path.split("/") {
		if part.starts_with(
			"."
		) or SKIP_DIRS.contains(part) { return true }
	}
	return false
}

fn category_of(relative String) List[String] {
	var rel = relative.clone()
	if rel.ends_with(".ms") {
		rel = rel.slice(0, rel.length() - 3).clone()
	}
	if rel.starts_with("tests/e2e/testdata/") {
		rel = rel.slice("tests/e2e/testdata/".length(), rel.length()).clone()
	}

	parts := rel.split("/")
	first := parts[0].clone()
	var category = "repo"

	if (
		first == "accept"
		or first == "reject"
		or first == "stdlib"
		or first == "projects"
		or first == "shutdown"
	) {
		category = f"e2e/{first}"
	} else if first == "bench" or first == "examples" {
		category = first.clone()
	}

	var rest = rel.replace("/", "-")
	if category.starts_with("e2e/") or (category != "repo" and parts.length() > 1) {
		rest = parts.drop(1).join("-")
	}
	return [category, slugify(rest)]
}

// The directory of `tests/` that a harvested category lands in;
// `tools/conform.ms retag` and a later regrouping move a fixture to its feature.
fn placed(category String) String {
	if category == "e2e/stdlib" { return "lang/stdlib" }
	if category == "e2e/projects" { return "lang/projects" }
	if category == "e2e/reject" { return "diagnostics/harvested" }

	return f"lang/{category.replace("/", "-")}"
}

// Whether `path` is inside the fixture directories of `tests/`.
fn in_corpus(path String) Bool {
	return (
		path.starts_with("tests/lang/")
		or path.starts_with("tests/diagnostics/")
		or path.starts_with("tests/format/")
	)
}

// Candidates found by walking the repository.
fn scan_tree(repo String) List[Candidate] {
	var projects = List[String]()

	for entry in glob(repo, GlobOptions(patterns: ["**/ms.toml"])).get_or([]) {
		if skipped(entry.path) or in_corpus(entry.path) { continue }

		dir := entry.path.slice(0, parent_length(entry.path))
		if dir != "" { projects.append(dir.clone()) }
	}

	var found = List[Candidate]()
	var files = List[String]()

	for entry in glob(repo, GlobOptions(patterns: ["**/*.ms"])).get_or([]) {
		if skipped(entry.path) { continue }
		if (entry.path.starts_with("src/stdlib/") or in_corpus(entry.path)) { continue }

		var inside = false
		for project in projects {
			if entry.path.starts_with(
				f"{project}/"
			) { inside = true }
		}
		if not inside { files.append(entry.path.clone()) }
	}

	files.sort()

	for path in files {
		parts := category_of(path)
		found.append(
			Candidate(
				origin: path.clone(),
				category: parts[0].clone(),
				slug: parts[1].clone(),
				is_project: false,
				text: read_text(f"{repo}/{path}"),
				dir: "",
			)
		)
	}

	projects.sort()

	for dir in projects {
		parts := category_of(dir)
		found.append(
			Candidate(
				origin: dir.clone(),
				category: parts[0].clone(),
				slug: parts[1].clone(),
				is_project: true,
				text: "",
				dir: f"{repo}/{dir}",
			)
		)
	}

	return found
}

// Candidates from ```manuscript fences under `documentation/`.
fn scan_docs(repo String) List[Candidate] {
	var found = List[Candidate]()
	var files = glob(f"{repo}/documentation", GlobOptions(patterns: ["**/*.md"])).get_or(
		[]
	).map(entry => (entry.path.clone()))
	files.sort()

	for file in files {
		relative := f"documentation/{file}"
		stem := slugify(file.replace(".md", ""))
		var n = 0
		var start = 0
		var inside = false
		var body = ""
		var at = 0

		for line in read_text(f"{repo}/{relative}").split("\n") {
			at += 1

			if not inside {
				if line.starts_with("```manuscript") {
					inside = true
					start = at
					body = ""
				}

				continue
			}

			if line.starts_with("```") {
				n += 1
				found.append(
					Candidate(
						origin: f"{relative}:{start}",
						category: "docs",
						slug: f"{stem}-{n}",
						is_project: false,
						text: body.clone(),
						dir: "",
					)
				)
				inside = false
			} else {
				body += line + "\n"
			}
		}
	}

	return found
}

fn unusable(reason String) Verdict {
	return Verdict(parse_errors: false, type_errors: false, unusable: reason.clone())
}

// Copies the project at `from` into `to` without hidden or build directories and
// without harness files.
fn copy_project(from, to String) Void {
	void create_directory(to.slice(0, parent_length(to)).clone(), recursive: true).get()
	void copy(from, to, CopyOptions(recursive: true, replace: true)).get()
	for pattern in [
		"**/*.expected.json", "**/conform.meta", "**/.*", "**/node_modules",
		"**/target", "**/vendor", "**/dist"
	] {
		for entry in glob(to, GlobOptions(patterns: [pattern])).get_or([]) {
			void remove(f"{to}/{entry.path}", recursive: true)
		}
	}
}

fn check_candidate(ms, scratch String, index Int, candidate Candidate) Verdict {
	work := f"{scratch}/c{index}"
	void remove(work, recursive: true)

	var entry = "main.ms"

	if candidate.is_project {
		copy_project(candidate.dir, work)
		entry = "ms.toml"
	} else {
		void create_directory(work.clone(), recursive: true).get()
		if write_file(f"{work}/main.ms", candidate.text, replace: true).wait().is_error() {
			return unusable("cannot write scratch file")
		}
	}

	result := run(
		ms,
		["check", "--only", "types", entry, "--json"],
		RunOptions(cwd: work.clone(), timeout: seconds(120)),
	).wait()
	void remove(work, recursive: true)
	if result.is_error() { return unusable("check timed out or did not start") }

	report := parse(text_of(result.get().stdout)).get_or(JsonValue.Null)
	if report == JsonValue.Null { return unusable("check printed no JSON") }

	var verdict = Verdict(parse_errors: false, type_errors: false, unusable: "")
	listed := report.get("diagnostics")

	if listed != null {
		for diagnostic in (listed.as_list() or []) {
			phase := diagnostic.get("phase")

			if phase != null and (phase.as_string() or "") == "parse" {
				verdict.parse_errors = true
			} else {
				verdict.type_errors = true
			}
		}
	}

	return verdict
}

fn check_chunk(ms, scratch String, base Int, chunk List[Candidate]) List[Verdict] {
	verdicts := (0..chunk.length()).map(
		offset => check_candidate(ms, scratch, base + offset, chunk[offset])
	)
	return verdicts
}

fn has_test_blocks(text String) Bool {
	return text.contains("\ntest \"") or text.starts_with("test \"")
}

fn has_main(text String) Bool {
	return text.contains("export fn main(")
}

// The text of a project directory's sources, to classify and tag it.
fn project_text(dir String) String {
	var text = ""

	for entry in glob(dir, GlobOptions(patterns: ["**/*.ms", "ms.toml"])).get_or([]) {
		if skipped(entry.path) { continue }

		text += read_text(f"{dir}/{entry.path}") + "\n"
	}

	return text
}

fn header(origin, phase, text String, extra List[String]) Meta {
	var tags = tags_for(text, phase)
	tags.extend(extra)
	return Meta(
		tags: sorted_unique(tags),
		phase: phase.clone(),
		phases: [phase.clone()],
		args: [],
		timeout: 0,
		entry: "",
		origin: origin.clone(),
		deterministic: false,
	)
}

fn strip_headers(source String) String {
	var lines = source.split("\n")
	var skipped_lines = 0
	while (
		skipped_lines < lines.length()
		and lines[skipped_lines].starts_with("// conform:")
	) { skipped_lines += 1 }
	return lines.drop(skipped_lines).join("\n")
}

fn write_source(corpus, id, origin, phase, body String, extra List[String]) Bool {
	path := f"{corpus}/{id}.ms"
	void create_directory(path.slice(0, parent_length(path)).clone(), recursive: true).get()

	var text = render_meta(header(origin, phase, body, extra)) + body
	if not text.ends_with("\n") { text += "\n" }
	return write_file(path, text, replace: true).wait().is_ok()
}

fn write_single(
	corpus,
	id String,
	candidate Candidate,
	verdict Verdict,
	twins Bool,
) List[String] {
	body := strip_headers(candidate.text)
	var phase = "check"

	if verdict.parse_errors {
		phase = "parse"
	} else if verdict.type_errors {
		phase = "check"
	} else if has_test_blocks(body) {
		phase = "test"
	} else if not hostile(body) and has_main(body) {
		phase = "run"
	}

	var written = List[String]()
	if write_source(corpus, id, candidate.origin, phase, body, []) {
		written.append(phase.clone())
	}

	// A run/test/check program that is syntactically valid also pins the formatter.
	if twins and not verdict.parse_errors {
		if write_source(
			corpus,
			f"{id}-fmt",
			candidate.origin,
			"parse",
			body,
			["formatter"],
		) { written.append("parse") }
	}
	if phase == "test" and has_main(body) {
		if write_source(corpus, f"{id}-run", candidate.origin, "run", body, []) {
			written.append("run")
		}
	}
	return written
}

fn write_project(corpus, id String, candidate Candidate, verdict Verdict) List[String] {
	text := project_text(candidate.dir)
	var phase = "check"

	if verdict.parse_errors or verdict.type_errors {
		phase = "check"
	} else if has_test_blocks(text) {
		phase = "test"
	} else if not hostile(text) and has_main(text) {
		phase = "run"
	}

	var phases = [phase.clone()]
	if phase == "test" and not hostile(text) and has_main(text) {
		phases.append("run")
	}

	var written = List[String]()

	for index in 0..phases.length() {
		target := if index == 0 { f"{corpus}/{id}" } else { f"{corpus}/{id}-run" }
		void remove(target, recursive: true)
		copy_project(candidate.dir, target)

		var meta = header(candidate.origin, phases[index], text, ["projects"])
		if phases[index] == "run" { meta.timeout = 120 }
		void write_file(f"{target}/conform.meta", render_meta(meta), replace: true).wait().get()
		written.append(phases[index].clone())
	}

	return written
}

export fn harvest(root, corpus String, args Args) Int {
	repo := one(args, "repo", root)
	ms := one(args, "ms", tool_ms(root))
	var candidates = List[Candidate]()
	if not has(args, "no-tree") {
		candidates.extend(scan_tree(repo))
	}
	if not has(args, "no-docs") {
		candidates.extend(scan_docs(repo))
	}
	print(f"{candidates.length()} candidates")

	// Identical sources are one fixture.
	var seen = List[String]()
	var unique = List[Candidate]()
	var duplicates = 0

	for candidate in candidates {
		if not candidate.is_project {
			key := candidate.text.trim().clone()

			if key == "" or seen.contains(key) {
				duplicates += 1
				continue
			}

			seen.append(key)
		}

		unique.append(candidate.clone())
	}

	scratch := temporary("ms-conform-harvest-").get()
	var jobs = number(args, "jobs", system_info().cpu_count)
	if jobs > 8 { jobs = 8 }
	if jobs < 1 { jobs = 1 }

	var chunks = List[List[Candidate]]()
	var bases = List[Int]()
	size := (unique.length() + jobs - 1) / jobs
	var start = 0

	while start < unique.length() {
		var end = start + size
		if end > unique.length() { end = unique.length() }
		chunks.append(unique.drop(start).take(end - start))
		bases.append(start)
		start = end
	}

	var tasks = List[Promise[List[Verdict]]]()

	for index in 0..chunks.length() {
		tool := ms.clone()
		dir := scratch.path().clone()
		base := bases[index]
		mine := chunks[index].clone()
		tasks.append(promise(() => ok(check_chunk(tool, dir, base, mine))))
	}

	var verdicts = List[Verdict]()
	for task in tasks {
		verdicts.extend(task.wait().get_or([]))
	}

	var used = List[String]()
	var written = 0
	var problems = List[String]()
	var by_phase = Map[String, Int]()

	for index in 0..unique.length() {
		candidate := unique[index].clone()
		verdict := verdicts[index].clone()

		if verdict.unusable != "" {
			problems.append(f"UNUSABLE {candidate.origin}: {verdict.unusable}")
			continue
		}

		var id = f"{placed(candidate.category)}/{candidate.slug}"
		var n = 1

		while used.contains(id) {
			n += 1
			id = f"{placed(candidate.category)}/{candidate.slug}-{n}"
		}

		used.append(id.clone())

		phases := if candidate.is_project {
			write_project(corpus, id, candidate, verdict)
		} else {
			write_single(corpus, id, candidate, verdict, not has(args, "no-twins"))
		}

		for phase in phases {
			written += 1
			by_phase.add(phase.clone(), (by_phase.get(phase) or 0) + 1)
		}
	}

	print(
		f"{written} fixtures written, {duplicates} duplicates dropped, {problems.length()} unusable"
	)
	for phase in ["parse", "check", "run", "test"] {
		print(f"  {phase}: {(by_phase.get(phase) or 0)}")
	}
	for problem in problems { print(problem) }
	return 0
}
