// System prompt assembly: tool guidance, project context files, date and working directory.
import (
	skills_prompt from "./extend.ms",
	read_file from "@std/os/fs.ms",
	working_directory from "@std/os/env.ms",
	dirname, join from "@std/os/path.ms",
	now from "@std/time.ms",
)

fn describe(tool: String) String:
	if tool == "read": return "read: Read file contents"
	if tool == "bash": return "bash: Execute bash commands (ls, grep, find, etc.)"
	if tool == "edit": return "edit: Make surgical edits to files (find exact text and replace)"
	if tool == "write": return "write: Create or overwrite files"
	if tool == "grep": return "grep: Search file contents for patterns"
	if tool == "find": return "find: Find files by glob pattern"
	if tool == "ls": return "ls: List directory contents"

	return tool.clone()

// Contents of AGENTS.md or CLAUDE.md in `dir`, if present.
fn context_file(dir: String) String?:
	for name in ["AGENTS.md", "CLAUDE.md"]:
		path := join([dir.clone(), name.clone()])
		if data := read_file(path, 262144).wait().to_optional():
			if text := data.decode_utf8(): return "## {path}\n\n{text}"

	return none

// Context files from the filesystem root down to the working directory.
fn context_files() String:
	cwd := working_directory().get("/")
	var dirs = List[String]()
	var dir = cwd.clone()

	while true:
		dirs.prepend(dir.clone())

		parent := dirname(dir)
		if parent == dir: break

		dir = parent

	var found = List[String]()
	for d in dirs:
		if text := context_file(d): found.append(text)
	return found.join("\n\n")

export fn build(tools: List[String], custom: String?, append: String) String:
	cwd := working_directory().get("")
	var out = ""

	if base := custom:
		out = base.clone()
	else:
		listing := tools.map(fn t: "- {describe(t)}").join("\n")
		out = "You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.\n\nAvailable tools:\n{listing}\n\nGuidelines:\n- Use bash for file operations like ls, rg, find\n- Use read to examine files before editing; use edit for precise changes and write only for new files or complete rewrites\n- When summarizing your actions, output plain text directly; do not use cat or bash to display what you did\n- Be concise in your responses\n- Show file paths clearly when working with files"

	if not append.is_empty(): out = "{out}\n\n{append}"

	skills := skills_prompt()
	if not skills.is_empty(): out = "{out}\n\n{skills}"

	files := context_files()
	if not files.is_empty(): out = "{out}\n\n# Project Context\n\n{files}"
	return "{out}\n\nCurrent date: {now().format("%Y-%m-%d", "UTC").get("")}\nCurrent working directory: {cwd}"
