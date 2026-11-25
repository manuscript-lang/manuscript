// Expectations written in a fixture's own file, so a test reads as one file. They are
// the last lines, after the program, so the line numbers in them are the file's own:
//
//     // expect-error: MS3000 9:9 cannot change `xs` while `ys` borrows it
//     // expect-error: MS1000 8:10-8:13 'try' was replaced by a postfix '?'
//     // expect-fix: 3:13-3:14 ":="
//     // expect-exit: 0
//
// `render` turns an observed check report into these lines; the runner compares them
// with the lines of the file. `expect-exit` is written when there are no diagnostics or
// the exit code is not 1.
import JsonValue, stringify from "@std/data/json.ms"

fn number_of(value JsonValue, key String) Int {
	return (value.get(key) or JsonValue.Null).as_int() or 0
}

fn place(position JsonValue) String {
	return f"{number_of(position, "line")}:{number_of(position, "column")}"
}

fn span(start, end JsonValue) String {
	return f"{place(start)}-{place(end)}"
}

// `text` with line breaks and backslashes escaped so that it stays on one line.
export fn escaped(text String) String {
	return text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
}

// The expectation lines of one observed diagnostic.
fn diagnostic_lines(one JsonValue) List[String] {
	var lines = List[String]()
	code := (one.get("code") or JsonValue.Null).as_string() or ""
	message := (one.get("message") or JsonValue.Null).as_string() or ""
	start := one.get("position") or JsonValue.Null
	end := one.get("end")
	var where = place(start)
	if end != null { where = span(start, end) }
	lines.append(f"expect-error: {code} {where} {escaped(message)}")

	fix := one.get("fix")

	if fix != null {
		replacement := (fix.get("replacement") or JsonValue.Null).as_string() or ""
		fix_start := fix.get("position") or JsonValue.Null
		fix_end := fix.get("end") or fix_start
		lines.append(
			f"expect-fix: {span(fix_start, fix_end)} {stringify(JsonValue.StringValue(replacement.clone())).get()}"
		)
	}

	return lines
}

// The expectation lines of an observed `check` report, without the `// ` prefix.
export fn render(observed JsonValue) List[String] {
	listed := observed.get("diagnostics")
	exit := observed.get("exit_code")
	if listed == null or exit == null { return ["expect-unobserved"] }

	diagnostics := listed.as_list() or []
	var lines = List[String]()
	for one in diagnostics {
		lines.extend(diagnostic_lines(one))
	}

	code := exit.as_int() or (-1)
	if diagnostics.is_empty() or code != 1 {
		lines.append(f"expect-exit: {code}")
	}
	return lines
}

// Whether `line` belongs to the trailing expectation block.
fn expectation(line String) Bool {
	return line.trim().starts_with("// expect-")
}

// The lines of `text` without its trailing expectation block.
fn program_lines(text String) List[String] {
	var lines = text.split("\n").collect().map(line => line.clone())

	// A final newline leaves one empty element.
	while not lines.is_empty() and lines[lines.length() - 1].trim() == "" {
		lines = lines.slice(0, lines.length() - 1).get().clone()
	}
	while not lines.is_empty() and expectation(lines[lines.length() - 1]) {
		lines = lines.slice(0, lines.length() - 1).get().clone()
	}
	return lines
}

// The expectation lines at the end of `text`, without the `// ` prefix. They follow the
// program, so line numbers in them are the file's own.
export fn inline_lines(text String) List[String] {
	var lines = List[String]()
	var at = text.split("\n").collect().length()
	all := text.split("\n").collect().map(line => line.clone())

	while at > 0 {
		at -= 1

		line := all[at].trim()
		if line == "" and lines.is_empty() { continue }
		if not line.starts_with("// expect-") { break }

		lines.insert(0, line.slice(3, line.length()).clone())
	}

	return lines
}

// `text` with its trailing expectation block replaced by `lines`.
export fn with_lines(text String, lines List[String]) String {
	var out = program_lines(text)
	for line in lines {
		out.append(f"// {line}")
	}
	return out.join("\n") + "\n"
}
