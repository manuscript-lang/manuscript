// Embedded example check (`docs-check`): every `manuscript` fence in the book, the
// standard-library descriptions and the agent skill must still be valid Manuscript, so
// a syntax change that leaves a stale example fails the build. A fence carries a marker
// line above it, `<!-- manuscript-example: {"mode":"check"} -->`, naming how it is
// checked:
//   check     the fence is a whole module and must pass `ms check`
//   test      the fence is a whole module and its `test` blocks must pass `ms test`
//   bench     like run: the fence is a whole program with `bench` blocks
//   run       the fence is a whole program and must pass `ms check`; the book's example
//             tests run it and compare `stdout`
//   error     `ms check` must fail and print `contains`; a marker with `given` makes the
//             fence a snippet, checked like a fragment
//   fragment  a snippet. It is wrapped in a function with `given` as its parameters, after
//             `context`; with `given` it must type-check, without it only parse.
// A fence with no marker is a fragment that only parses, and under `documentation/` and
// `src/stdlib/` it is itself an error. Usage: ms run tools/example-check.ms [-- files]
import (
	parse from "@std/data/json.ms",
	arguments, working_directory from "@std/os/env.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	capture, env, tool_ms from "./lib.ms",
)

type Marker {
	mode String
	given List[String]?
	context, contains String?
}

type Example {
	file String
	line Int
	mode String
	given List[String]
	snippet, typed Bool
	context, contains String
	marked Bool
	code String
}

// Where the examples live: the book, the standard-library descriptions, the agent
// skill, the wiki and the repository README. Design proposals are history and stay out.
fn scanned(path String) Bool {
	if path == "README.md" { return true }
	if path.starts_with(
		"documentation/"
	) and path.ends_with(
		".md"
	) { return true }
	if path.starts_with(
		"design/wiki/"
	) and path.ends_with(
		".md"
	) { return true }
	if path.starts_with(
		"extensions/agent-skill/"
	) and path.ends_with(
		".md"
	) { return true }
	if path.starts_with(
		"skills/"
	) and path.ends_with(
		".md"
	) { return true }

	return path.starts_with("src/stdlib/") and path.ends_with(".ms")
}

// Whether a fence without a marker is an error in this file.
fn needs_marker(path String) Bool {
	return path.starts_with("documentation/") or path.starts_with("src/stdlib/")
}

fn is_open(line String) Bool {
	for tag in ["```manuscript", "```ms"] {
		if line == tag or line.starts_with(tag + " ") or line.starts_with(
			tag + "{"
		) { return true }
	}
	return false
}

// The marker JSON on a `<!-- manuscript-example: {...} -->` line, or empty.
fn marker_json(line String) String {
	head := "<!-- manuscript-example: "
	if not line.starts_with(
		head
	) or not line.ends_with(" -->") { return "" }

	return line.slice(head.length(), line.length() - 4).clone()
}

// A `//` line comment's text, without the slashes and the one space after them; a line
// that is not a comment is returned unchanged.
fn uncomment(line String) String {
	text := line.trim_start()
	if text == "//" { return "" }
	if text.starts_with("// ") {
		return text.slice(3, text.length()).clone()
	}

	return line.clone()
}

// Whether `line` is a `//` line comment.
fn is_comment(line String) Bool {
	return line.trim_start().starts_with("//")
}

// The examples of one file. A fence written in `//` comments is read with the slashes
// removed.
fn examples_of(path, text String, var problems List[String]) List[Example] {
	var found = List[Example]()
	lines := text.split("\n")
	var at = 0

	while at < lines.length() {
		commented := path.ends_with(".ms") and is_comment(lines[at])
		opener := if commented { uncomment(lines[at]).trim_end() } else { lines[at].trim_end() }

		if not is_open(opener) {
			at += 1
			continue
		}

		var example = Example(
			file: path.clone(),
			line: at + 1,
			mode: "fragment",
			given: [],
			snippet: false,
			typed: false,
			context: "",
			contains: "",
			marked: false,
			code: "",
		)

		if at > 0 {
			above := if commented { uncomment(lines[at - 1]) } else { lines[at - 1] }
			json := marker_json(above.trim_end())

			if json != "" {
				example.marked = true

				if m := parse[Marker](json) {
					example.mode = m.mode.clone()
					example.given = (m.given or []).clone()
					example.typed = m.given != null
					example.snippet = example.typed or m.mode == "fragment"
					example.context = (m.context or "").clone()
					example.contains = (m.contains or "").clone()
				} else {
					problems.append(
						f"{path}:{at}: the marker is not valid JSON with a mode"
					)
				}
			}
		}

		var body = List[String]()
		var close = at + 1

		while close < lines.length() {
			row := if commented { uncomment(lines[close]) } else { lines[close].clone() }
			if row.trim_end() == "```" { break }

			body.append(row)
			close += 1
		}

		example.code = body.join("\n") + "\n"
		if not example.marked and needs_marker(path) {
			problems.append(
				f"{path}:{at + 1}: add a `manuscript-example` marker above this fence, or use a `text` fence"
			)
		}
		found.append(example)
		at = close + 1
	}

	return found
}

// How many times `mark` occurs in `line`.
fn occurrences(line, mark String) Int {
	return line.split(mark).length() - 1
}

// Whether `line` starts a top-level declaration.
fn starts_declaration(line String) Bool {
	for word in ["type ", "enum ", "interface ", "fn ", "export ", "test "] {
		if line.starts_with(word) { return true }
	}
	return false
}

// The source `ms` checks for a fragment: imports first, then `context`, then the
// snippet. Wrapped, the snippet's own declarations stay at the top level and its
// statements become the body of a function whose parameters are `given`.
fn fragment_source(e Example, wrap Bool) String {
	var imports = List[String]()
	var declarations = List[String]()
	var statements = List[String]()
	var open = 0
	var inside = false

	for line in e.code.split("\n") {
		if not inside and line.starts_with("import ") {
			imports.append(line.clone())
			continue
		}

		if wrap and not inside and starts_declaration(line) { inside = true }

		if not (wrap and inside) {
			statements.append(line.clone())
			continue
		}

		declarations.append(line.clone())
		open += (
			occurrences(line, "{")
			+ occurrences(line, "(")
			- occurrences(line, "}")
			- occurrences(line, ")")
		)

		if open <= 0 {
			inside = false
			open = 0
		}
	}

	head := imports.join("\n") + "\n" + e.context + "\n"
	if not wrap {
		return head + statements.join("\n") + "\n"
	}

	var body = statements.join("\n")
	var code_lines = 0
	for line in statements {
		if line.trim() != "" and not line.trim().starts_with(
			"//"
		) { code_lines += 1 }
	}
	if code_lines == 0 { body = "return ok()" }
	return (
		head
		+ declarations.join("\n")
		+ "\nfn example_fragment("
		+ e.given.join(", ")
		+ ") Void! {\n"
		+ body
		+ "\n}\n"
	)
}

type Outcome {
	code Int
	text String
}

// The diagnostics of `text` that matter to a snippet: a name it only introduces to show
// a form is allowed to go unread.
fn real_errors(text String) List[String] {
	var found = List[String]()

	for line in text.split("\n") {
		if not line.contains(
			".ms:"
		) { continue }
		if line.contains("never read") { continue }

		found.append(line.clone())
	}

	return found
}

// Runs `ms <command> <file>` and returns the exit code and what it printed.
fn ms_run(ms, command, path String) Outcome {
	opts := RunOptions(timeout: seconds(120), env: Map[String, String]())
	if out := run(ms.clone(), [command.clone(), path.clone()], opts).wait() {
		return Outcome(
			code: out.exit_code,
			text: (out.stdout.decode_utf8() or "") + (
				out.stderr.decode_utf8()
				or ""
			),
		)
	}

	return Outcome(code: 125, text: "ms did not run")
}

// Checks a snippet. One that names its `given` parameters is a function body, wrapped;
// one that does not is parsed as a module first, since it may hold only declarations,
// and wrapped when that fails to parse.
fn check_snippet(ms, scratch String, e Example, n Int) Outcome {
	if not e.typed {
		path := f"{scratch}/e{n}.ms"
		write_file(path.clone(), fragment_source(e, false)).wait().get()

		whole := ms_run(ms, "check", path)
		if not whole.text.contains(
			"parse:"
		) { return whole }
	}

	wrapped_path := f"{scratch}/e{n}w.ms"
	write_file(wrapped_path.clone(), fragment_source(e, true)).wait().get()

	wrapped := ms_run(ms, "check", wrapped_path)
	if wrapped.code != 0 and real_errors(wrapped.text).is_empty() {
		return Outcome(code: 0, text: wrapped.text)
	}

	return wrapped
}

// The reason an example is stale, or empty.
fn verdict(ms, scratch String, e Example, n Int) String {
	if e.mode == "fragment" {
		result := check_snippet(ms, scratch, e, n)
		if not e.typed and not result.text.contains(
			"parse:"
		) { return "" }
		if result.code == 0 { return "" }

		return first_line(result.text)
	}

	if e.mode == "error" {
		var result = Outcome(code: 0, text: "")

		if e.snippet {
			result = check_snippet(ms, scratch, e, n)
		} else {
			path := f"{scratch}/e{n}.ms"
			write_file(path.clone(), e.code).wait().get()
			result = ms_run(ms, "check", path)
		}

		if result.code == 0 { return "the example is marked `error` but passes `ms check`" }
		if not result.text.contains(
			e.contains
		) { return f"the diagnostic does not contain `{e.contains}`: {first_line(result.text)}" }

		return ""
	}

	path := f"{scratch}/e{n}.ms"
	write_file(path.clone(), e.code).wait().get()

	if e.mode == "check" or e.mode == "run" or e.mode == "bench" {
		result := ms_run(ms, "check", path)
		if result.code == 0 { return "" }

		return first_line(result.text)
	}

	if e.mode == "test" {
		result := ms_run(ms, "test", path)
		if result.code == 0 { return "" }

		return first_line(result.text)
	}

	return f"unknown mode `{e.mode}`"
}

fn first_line(text String) String {
	for line in text.split("\n") {
		if line.trim() != "" { return line.clone() }
	}
	return "failed with no output"
}

fn main() Int {
	root := working_directory().get()
	ms := tool_ms(root.clone())
	var files = List[String]()
	for f in arguments() { files.append(f.clone()) }

	if files.is_empty() {
		listing := capture(env("GIT", "git"), ["ls-files"])
		for line in listing.split("\n") {
			if scanned(line.trim()) {
				files.append(line.trim().clone())
			}
		}
	}

	if files.is_empty() {
		print("no files to scan; run from the repository root with git on PATH")
		return 1
	}

	scratch := temporary("ms-examples-").get()
	var problems = List[String]()
	var count = 0

	for f in files {
		bytes := read_file(f.clone()).wait()
		if bytes.is_error() { continue }

		text := (bytes.get().decode_utf8() or "").replace("\r\n", "\n")

		for e in examples_of(f, text, problems) {
			count += 1

			why := verdict(ms, scratch.path(), e, count)
			if why != "" {
				problems.append(f"{e.file}:{e.line}: [{e.mode}] {why}")
			}
		}
	}

	for p in problems { print(p) }
	print(f"checked {count} examples, {problems.length()} stale")
	if count == 0 { return 1 }
	if not problems.is_empty() { return 1 }

	return 0
}
