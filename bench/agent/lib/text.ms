// Small helpers shared by the benchmark tools: environment, files, shell commands.
import (
	environment from "@std/os/env.ms",
	create_directory, read_file, write_file from "@std/os/fs.ms",
	dirname from "@std/os/path.ms",
	RunOptions, run from "@std/os/process.ms",
	compile from "@std/regex.ms",
	monotonic, seconds from "@std/time.ms",
)

// The value of environment variable `name`, or `fallback`.
export fn env(name String, fallback String) String:
	all := environment().get_or(Map[String, String]())
	value := all.get(name)
	if value != null: return value.clone()

	return fallback.clone()

// The text of the file at `path`; empty when it cannot be read.
export fn read_text(path String) String:
	data := read_file(path).wait().to_optional()
	if data != null: return (data.decode_utf8() or "")

	return ""

// The text of the file at `path`; a missing file stops the program.
export fn must_read(path String) String:
	return read_file(path).wait().get().decode_utf8() or ""

// Replaces the file at `path`, creating its directory first.
export fn write_text(path String, text String) Void:
	create_directory(dirname(path), recursive: true).get()
	write_file(path, text, replace: true).wait().get()

// Trailing whitespace removed from every line and from the whole text, as the graders
// compare output.
export fn norm(text String) String:
	if text.trim().is_empty(): return ""
	return text.trim_end().split("\n").map(line => line.trim_end()).join("\n")

// The nonblank lines of `text`.
export fn nonblank_lines(text String) List[String]:
	return text.split("\n").filter(l => not l.trim().is_empty())

// What a finished shell command left behind.
export type Ran:
	code Int
	out String
	err String
	seconds Float

// Runs `command` with `bash -c` in directory `cwd`, feeding it `input`. A command still
// running after
// `timeout_s` seconds is killed and reports status 124 with "timeout" on standard error.
export fn bash(command String, cwd String, timeout_s Int, input String) Ran:
	return run_in(
		"bash",
		["-c", f"cd \"$0\" && {command}", cwd.clone()],
		timeout_s,
		input,
	)

// Runs `program` with `arguments` and the same timeout rule as `bash`.
export fn run_in(
	program String,
	arguments List[String],
	timeout_s Int,
	input String,
) Ran:
	start := monotonic()
	result := run(
		program,
		arguments,
		RunOptions(input: input.to_bytes(), timeout: seconds(timeout_s)),
	).wait()
	elapsed := monotonic().difference(start).nanos.to_float() / 1000000000.0
	done := result.clone().to_optional()
	if done != null:
		return Ran(
			done.exit_code,
			done.stdout.decode_utf8() or "",
			done.stderr.decode_utf8() or "",
			elapsed,
		)
	if result.err().kind == "ETIMEDOUT": return Ran(124, "", "timeout", elapsed)

	return Ran(127, "", f"cannot start {program}", elapsed)

// `text.split(separator, maxsplit)` as Python defines it: at most `splits` splits, the rest stays in the last piece.
export fn split_max(text String, separator String, splits Int) List[String]:
	var out = List[String]()
	var rest = text.clone()

	while out.length() < splits:
		at := rest.index_of(separator)
		if at == null: break

		out.append(rest.slice(0, at))
		rest = rest.slice((at) + separator.length(), rest.length())

	out.append(rest)
	return out

// `text.strip(" ")`: the spaces at both ends removed.
export fn strip_spaces(text String) String:
	var start = 0
	var end = text.length()
	while start < end and text.scalar_at(start, -1) == 32: start += 1
	while end > start and text.scalar_at(end - 1, -1) == 32: end -= 1
	return text.slice(start, end)

// Whether the regular expression `pattern` matches all of `text`, as Python's
// `re.fullmatch`.
export fn full_match(pattern String, text String) Bool:
	re := compile(f"^(?:{pattern})$").to_optional()
	if re != null: return re.matches(text)

	return false

// `text.split()`: the words between runs of whitespace.
export fn words(text String) List[String]:
	var out = List[String]()
	var current = ""

	for ch in text.chars():
		if ch.trim().is_empty():
			if current != "": out.append(current.clone())
			current = ""
		else:
			current += ch

	if current != "": out.append(current.clone())
	return out
