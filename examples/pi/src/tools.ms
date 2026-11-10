// Built-in coding tools: read, write, edit, bash, ls, grep, find.
import (
	PromiseOptions, Signal from "@std/concurrency/promise.ms",
	JsonValue, parse from "@std/data/json.ms",
	read_file, write_file, create_directory, list from "@std/os/fs.ms",
	dirname, join, is_absolute from "@std/os/path.ms",
	run, RunOptions from "@std/os/process.ms",
	working_directory from "@std/os/env.ms",
	seconds from "@std/time.ms",
	str, obj, arr, str_or, int_or, flag_or from "./jsonx.ms",
)

export type ToolResult:
	text: String
	is_error: Bool

fn ok_text(text: String) ToolResult:
	return ToolResult(text: text, is_error: false)

fn fail(text: String) ToolResult:
	return ToolResult(text: text, is_error: true)

// Default caps, as in pi: 2000 lines or 50KB of output.
export max_lines := 2000
export max_bytes := 51200

export fn resolve_path(path: String) String:
	if is_absolute(path): return path.clone()

	cwd := working_directory().get("")
	return join([cwd, path.clone()])

fn property(kind: String, description: String) JsonValue:
	var p = Map[String, JsonValue]()
	p.add("type", str(kind))
	p.add("description", str(description))
	return obj(p)

fn schema(props: Map[String, JsonValue], required: List[String]) JsonValue:
	var s = Map[String, JsonValue]()
	s.add("type", str("object"))
	s.add("properties", obj(props))
	s.add("required", arr(required.map(fn r: str(r))))
	return obj(s)

fn tool(name: String, description: String, input: JsonValue) JsonValue:
	var t = Map[String, JsonValue]()
	t.add("name", str(name))
	t.add("description", str(description))
	t.add("input_schema", input)
	return obj(t)

// Names of every built-in tool, in pi's default order.
export fn all_tool_names() List[String]:
	return ["read", "bash", "edit", "write", "grep", "find", "ls"]

// Anthropic-style tool definitions for the enabled names.
export fn definitions(enabled: List[String]) List[JsonValue]:
	var out = List[JsonValue]()

	if enabled.contains("read"):
		var p = Map[String, JsonValue]()
		p.add(
			"path",
			property(
				"string", "Path to the file to read (relative or absolute)"
			)
		)
		p.add(
			"offset",
			property(
				"integer", "Line number to start reading from (1-indexed)"
			)
		)
		p.add("limit", property("integer", "Maximum number of lines to read"))
		out.append(
			tool(
				"read",
				"Read the contents of a file. Output is truncated to 2000 lines or 50KB; use offset and limit for large files.",
				schema(p, ["path"])
			)
		)

	if enabled.contains("bash"):
		var p = Map[String, JsonValue]()
		p.add("command", property("string", "Bash command to execute"))
		p.add(
			"timeout",
			property(
				"integer", "Timeout in seconds (optional, no default timeout)"
			)
		)
		out.append(
			tool(
				"bash",
				"Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to the last 2000 lines or 50KB.",
				schema(p, ["command"])
			)
		)

	if enabled.contains("edit"):
		var p = Map[String, JsonValue]()
		p.add(
			"path",
			property(
				"string", "Path to the file to edit (relative or absolute)"
			)
		)
		p.add(
			"oldText",
			property(
				"string", "Exact text to find and replace (must match exactly)"
			)
		)
		p.add("newText", property("string", "New text to replace the old text with"))
		out.append(
			tool(
				"edit",
				"Edit a file by replacing exact text. The oldText must match exactly, including whitespace, and occur once.",
				schema(p, ["path", "oldText", "newText"])
			)
		)

	if enabled.contains("write"):
		var p = Map[String, JsonValue]()
		p.add(
			"path",
			property(
				"string", "Path to the file to write (relative or absolute)"
			)
		)
		p.add("content", property("string", "Content to write to the file"))
		out.append(
			tool(
				"write",
				"Write content to a file. Creates the file if it does not exist, overwrites if it does, and creates parent directories.",
				schema(p, ["path", "content"])
			)
		)

	if enabled.contains("grep"):
		var p = Map[String, JsonValue]()
		p.add("pattern", property("string", "Search pattern (regex)"))
		p.add(
			"path",
			property(
				"string", "Directory or file to search (default: current directory)"
			)
		)
		p.add("glob", property("string", "Filter files by glob pattern, e.g. '*.ms'"))
		p.add("ignoreCase", property("boolean", "Case-insensitive search"))
		out.append(
			tool(
				"grep",
				"Search file contents for a pattern. Returns matching lines with file paths and line numbers.",
				schema(p, ["pattern"])
			)
		)

	if enabled.contains("find"):
		var p = Map[String, JsonValue]()
		p.add(
			"pattern",
			property(
				"string", "Glob pattern to match files, e.g. '*.ms' or '**/*.json'"
			)
		)
		p.add(
			"path",
			property(
				"string", "Directory to search in (default: current directory)"
			)
		)
		out.append(
			tool(
				"find",
				"Search for files by glob pattern. Returns matching file paths relative to the search directory.",
				schema(p, ["pattern"])
			)
		)

	if enabled.contains("ls"):
		var p = Map[String, JsonValue]()
		p.add(
			"path",
			property(
				"string", "Directory to list (default: current directory)"
			)
		)
		out.append(
			tool(
				"ls",
				"List directory contents, sorted alphabetically, with '/' suffix on directories.",
				schema(p, [])
			)
		)

	return out

// Keeps the first `max_lines` lines and `max_bytes` bytes, noting what was cut.
export fn truncate_head(text: String) String:
	lines := text.split("\n")
	if lines.length() <= max_lines and text.byte_length() <= max_bytes: return text.clone()

	var kept = List[String]()
	var used = 0

	for line in lines:
		if kept.length() >= max_lines or used + line.byte_length() + 1 > max_bytes: break

		kept.append(line.clone())
		used += line.byte_length() + 1

	return "{kept.join("\n")}\n\n[Truncated: showing {kept.length()} of {lines.length()} lines. Use offset/limit to read more.]"

// Keeps the last `max_lines` lines and `max_bytes` bytes: the end of command output matters most.
export fn truncate_tail(text: String) String:
	lines := text.split("\n")
	if lines.length() <= max_lines and text.byte_length() <= max_bytes: return text.clone()

	var kept = List[String]()
	var used = 0
	var i = lines.length() - 1

	while i >= 0:
		line := lines[i]
		if kept.length() >= max_lines or used + line.byte_length() + 1 > max_bytes: break

		kept.prepend(line.clone())
		used += line.byte_length() + 1
		i -= 1

	return "[Output truncated: last {kept.length()} of {lines.length()} lines]\n{kept.join("\n")}"

fn read_text(path: String) String!:
	data := try read_file(path).wait()
	if text := data.decode_utf8(): return ok(text)

	return error(Error("{path} is not valid UTF-8 text"))

fn tool_read(args: JsonValue) String!:
	path := str_or(args, "path", "")
	if path.is_empty(): return error(Error("Missing required argument: path"))

	text := try read_text(resolve_path(path))
	lines := text.split("\n")
	offset := int_or(args, "offset", 1)
	start := if offset > 1: offset - 1 else: 0
	if start >= lines.length(): return error(
		Error("Offset {offset} is beyond end of file ({lines.length()} lines)")
	)

	limit := int_or(args, "limit", lines.length())
	end := if start + limit < lines.length(): start + limit else: lines.length()
	body := (try lines.slice(start, end)).join("\n")
	result := truncate_head(body)
	if end < lines.length() and limit < lines.length():
		return ok(
			"{result}\n\n[{lines.length() - end} more lines in file. Use offset={end + 1} to continue.]"
		)

	return ok(result)

fn tool_write(args: JsonValue) String!:
	path := str_or(args, "path", "")
	if path.is_empty(): return error(Error("Missing required argument: path"))

	content := str_or(args, "content", "")
	full := resolve_path(path)
	try create_directory(dirname(full), recursive: true)
	try write_file(full, content, replace: true).wait()
	return ok("Successfully wrote {content.byte_length()} bytes to {path}")

fn tool_edit(args: JsonValue) String!:
	path := str_or(args, "path", "")
	old := str_or(args, "oldText", "")
	replacement := str_or(args, "newText", "")
	if path.is_empty() or old.is_empty(): return error(
		Error("Missing required arguments: path and oldText")
	)

	full := resolve_path(path)
	text := try read_text(full)
	n := text.count(old)
	if n == 0: return error(
		Error(
			"Could not find the exact text in {path}. The old text must match exactly including all whitespace and newlines."
		)
	)
	if n > 1: return error(
		Error(
			"Found {n} occurrences of the text in {path}. The text must be unique; include more context to make it unique."
		)
	)

	updated := text.replace_first(old, replacement)
	if updated == text: return error(
		Error(
			"No changes made to {path}: the replacement is identical to the original."
		)
	)

	try write_file(full, updated, replace: true).wait()
	return ok("Successfully replaced text in {path}.")

fn tool_bash(args: JsonValue, stop: Signal) String!:
	command := str_or(args, "command", "")
	if command.is_empty(): return error(Error("Missing required argument: command"))

	limit := int_or(args, "timeout", 0)
	options := RunOptions(
		cwd: working_directory().to_optional(),
		timeout: if limit > 0: seconds(limit) else: none, max_output_bytes: 16777216
	)
	out := try run("bash", ["-c", command], options).with(
		PromiseOptions(cancel: stop)
	).wait()
	stdout := out.stdout.decode_utf8().get("[binary output]")
	stderr := out.stderr.decode_utf8().get("[binary output]")
	text := truncate_tail("{stdout}{stderr}")
	if out.exit_code != 0: return error(
		Error("{text}\n\nCommand exited with code {out.exit_code}")
	)
	if text.is_empty(): return ok("(no output)")

	return ok(text)

fn tool_ls(args: JsonValue) String!:
	path := str_or(args, "path", ".")
	entries := try list(resolve_path(path))
	var names = entries.map(fn e: if e.directory: "{e.name}/" else: e.name.clone())
	names.sort()
	if names.is_empty(): return ok("(empty directory)")

	return ok(names.join("\n"))

fn tool_find(args: JsonValue) String!:
	pattern := str_or(args, "pattern", "")
	if pattern.is_empty(): return error(Error("Missing required argument: pattern"))

	path := str_or(args, "path", ".")
	flags := [
		resolve_path(path), "-path", "*/.git", "-prune", "-o", "-path",
		"*/node_modules", "-prune", "-o", "-name", pattern, "-print"
	]
	out := try run("find", flags).wait()
	text := out.stdout.decode_utf8().get("").trim()
	if text.is_empty(): return ok("No files found matching pattern")

	return ok(truncate_head(text))

fn tool_grep(args: JsonValue) String!:
	pattern := str_or(args, "pattern", "")
	if pattern.is_empty(): return error(Error("Missing required argument: pattern"))

	path := str_or(args, "path", ".")
	var flags = ["-rnE", "--exclude-dir=.git", "--exclude-dir=node_modules"]
	glob := str_or(args, "glob", "")
	if not glob.is_empty(): flags.append("--include={glob}")
	if flag_or(args, "ignoreCase", false): flags.append("-i")
	flags.append("-e")
	flags.append(pattern.clone())
	flags.append(resolve_path(path))

	out := try run("grep", flags).wait()
	text := out.stdout.decode_utf8().get("").trim()
	if text.is_empty(): return ok("No matches found")

	return ok(truncate_head(text))

fn dispatch(name: String, args: JsonValue, stop: Signal) String!:
	if name == "read": return tool_read(args)
	if name == "write": return tool_write(args)
	if name == "edit": return tool_edit(args)
	if name == "bash": return tool_bash(args, stop)
	if name == "ls": return tool_ls(args)
	if name == "find": return tool_find(args)
	if name == "grep": return tool_grep(args)

	return error(Error("Unknown tool: {name}"))

// Runs one tool call. Failures become error results the model can read.
export fn execute(name: String, args: JsonValue, stop: Signal) ToolResult:
	r := dispatch(name, args, stop)
	if r.is_error(): return fail(r.err().message)

	return ok_text(r.get(none))
