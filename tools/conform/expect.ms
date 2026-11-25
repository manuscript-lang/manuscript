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
	var lines = text.split("\n").map(line => line.clone())

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
	var at = text.split("\n").length()
	all := text.split("\n").map(line => line.clone())

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

// `text` on one comment line: escapes for backslash, line breaks, tabs and other control
// characters, and `\x20` for each trailing space, which the file would lose.
export fn encoded(text String) String {
	var out = ""

	for ch in text.split("") {
		if ch == "\\" {
			out += "\\\\"
		} else if ch == "\r" {
			out += "\\r"
		} else if ch == "\t" {
			out += "\\t"
		} else {
			out += ch
		}
	}

	var end = out.length()
	while end > 0 and out.slice(end - 1, end) == " " { end -= 1 }
	return out.slice(0, end) + "\\x20".repeat(out.length() - end)
}

// One `<key>: <text>` line, or `<key>:` when the text is empty.
fn keyed(key, text String) String {
	if text == "" { return f"{key}:" }
	return f"{key}: {encoded(text)}"
}

// The lines of captured output, one comment line apiece; output that does not end with
// a newline gains a closing `<key>-partial` line.
fn output_lines(key, text String) List[String] {
	var lines = List[String]()
	if text == "" { return lines }

	var parts = text.split("\n")
	partial := not text.ends_with("\n")
	if not partial { parts = parts.slice(
		0,
		parts.length() - 1,
	).get().clone() }
	for part in parts {
		lines.append(keyed(key, part))
	}
	if partial { lines.append(f"{key}-partial") }
	return lines
}

fn string_of(value JsonValue, key String) String {
	return (value.get(key) or JsonValue.Null).as_string() or ""
}

// The expectation lines of an observed `run`: exit status, stdout and stderr.
fn run_lines(observed JsonValue) List[String] {
	var lines = [f"expect-exit: {number_of(observed, "exit_code")}"]
	lines.extend(output_lines("expect-stdout", string_of(observed, "stdout")))
	lines.extend(output_lines("expect-stderr", string_of(observed, "stderr")))
	return lines
}

// The expectation lines of an observed `test`: exit status and the counts of its
// summary.
fn test_lines(observed JsonValue) List[String] {
	report := observed.get("report") or JsonValue.Null
	summary := report.get("summary") or JsonValue.Null
	var counts = f"passed={number_of(summary, "passed")} failed={number_of(summary, "failed")}"
	if number_of(summary, "skipped") > 0 {
		counts += f" skipped={number_of(summary, "skipped")}"
	}
	if number_of(summary, "not_run") > 0 {
		counts += f" not_run={number_of(summary, "not_run")}"
	}

	var lines = [
		f"expect-exit: {number_of(observed, "exit_code")}", f"expect-tests: {counts}"
	]
	lines.extend(output_lines("expect-stderr", string_of(observed, "stderr")))
	return lines
}

// The expectation lines of an observed `parse`: its parse diagnostics, then whether
// `ms fmt` leaves the program as it is, rewrites it (the result follows) or refuses it.
fn parse_lines(observed JsonValue) List[String] {
	var lines = List[String]()
	for one in (observed.get("diagnostics") or JsonValue.Null).as_list() or [] {
		lines.extend(diagnostic_lines(one))
	}

	code := observed.get("fmt_exit_code")

	if code != null {
		lines.append(f"expect-format-exit: {code.as_int() or (-1)}")
	} else if (observed.get("unchanged") or JsonValue.Null).as_bool() or false {
		lines.append("expect-format: unchanged")
	} else {
		lines.append("expect-format: rewritten")
		lines.extend(output_lines("expect-formatted", string_of(observed, "fmt")))
	}

	return lines
}

// The expectation lines of `observed` for `phase`.
export fn render_phase(phase String, observed JsonValue) List[String] {
	if phase == "run" { return run_lines(observed) }
	if phase == "test" { return test_lines(observed) }
	if phase == "parse" { return parse_lines(observed) }

	return render(observed)
}

// `text` without its trailing expectation block.
export fn program_text(text String) String {
	return program_lines(text).join("\n") + "\n"
}
