// Extension points: skills (SKILL.md), prompt templates (*.md) and external-process tools (*.json).
// Native code cannot load TypeScript extensions, so a tool extension is a command that reads the call's
// arguments as JSON on stdin and prints the result.
import (
	JsonValue, parse from "@std/data/json.ms",
	list, read_file from "@std/os/fs.ms",
	home_directory, working_directory from "@std/os/env.ms",
	join from "@std/os/path.ms",
	run, RunOptions from "@std/os/process.ms",
	str, render, str_or from "./jsonx.ms",
)

export type Skill:
	name: String
	description: String
	path: String

export type Template:
	name: String
	description: String
	body: String

fn user_dir() String:
	return join([home_directory().get(""), ".pi", "agent"])

fn project_dir() String:
	return join([working_directory().get("."), ".pi"])

fn read_text(path: String) String?:
	data := read_file(path, 1048576).wait().to_optional()
	if data.is_none(): return none

	return data.get("".to_bytes()).decode_utf8()

// Splits a `---` front matter block into key/value pairs and the remaining body.
type Document:
	fields: Map[String, String]
	body: String

fn split_document(text: String) Document:
	var fields = Map[String, String]()
	lines := text.split("\n")
	if lines.is_empty() or lines[0].trim() != "---": return Document(
		fields: fields, body: text.clone()
	)

	var i = 1

	while i < lines.length() and lines[i].trim() != "---":
		at := lines[i].index_of(":")
		if found := at:
			fields.add(
				lines[i].take(found).trim(),
				lines[i].drop(found + 1).trim().trim_chars("\"'")
			)
		i += 1

	return Document(fields: fields, body: lines.drop(i + 1).join("\n"))

fn skills_in(dir: String) List[Skill]:
	var out = List[Skill]()
	entries := list(dir).to_optional()
	if entries.is_none(): return out

	for entry in entries.get([]):
		if not entry.directory: continue

		path := join([dir.clone(), entry.name.clone(), "SKILL.md"])
		text := read_text(path)
		if text.is_none(): continue

		doc := split_document(text.get(""))
		out.append(
			Skill(
				name: doc.fields.get_or("name", entry.name),
				description: doc.fields.get_or("description", ""), path: path
			)
		)

	return out

export fn skills() List[Skill]:
	var all = skills_in(join([user_dir(), "skills"]))
	all.extend(skills_in(join([project_dir(), "skills"])))
	return all

// The skills block appended to the system prompt, or "" when there are none.
export fn skills_prompt() String:
	found := skills()
	if found.is_empty(): return ""

	items := found.map(
		fn s: "<skill>\n<name>{s.name}</name>\n<description>{s.description}</description>\n<location>{s.path}</location>\n</skill>"
	).join("\n")
	return "# Skills\n\nThe following skills provide specialized instructions for specific tasks. Use the read tool to load a skill's file when the task matches its description.\n\n<available_skills>\n{items}\n</available_skills>"

fn templates_in(dir: String) List[Template]:
	var out = List[Template]()
	entries := list(dir).to_optional()
	if entries.is_none(): return out

	for entry in entries.get([]):
		if entry.directory or not entry.name.ends_with(".md"): continue

		text := read_text(join([dir.clone(), entry.name.clone()]))
		if text.is_none(): continue

		doc := split_document(text.get(""))
		out.append(
			Template(
				name: entry.name.cut_suffix(".md").get(entry.name),
				description: doc.fields.get_or("description", ""), body: doc.body
			)
		)

	return out

export fn templates() List[Template]:
	var all = templates_in(join([user_dir(), "prompts"]))
	all.extend(templates_in(join([project_dir(), "prompts"])))
	return all

// Expands `$1`..`$9`, `$@` and `$ARGUMENTS` in a template body.
export fn expand(template: Template, args: List[String]) String:
	var body = template.body.replace("$ARGUMENTS", args.join(" ")).replace(
		"$@", args.join(" ")
	)
	var i = args.length()

	while i >= 1:
		body = body.replace("${i}", args[i - 1])
		i -= 1

	return body.trim()

// Parses `/name a b` and returns the expanded prompt when `name` is a template.
export fn from_command(line: String) String?:
	parts := line.drop(1).split(" ")
	name := parts[0].clone()
	found := templates().find(fn t: t.name == name)
	if t := found: return expand(t, parts.drop(1).filter(fn a: not a.is_empty()))

	return none

export type ExternalTool:
	name: String
	description: String
	command: List[String]
	schema: JsonValue

// Tools declared in ~/.pi/agent/extensions/*.json and .pi/extensions/*.json.
export fn external_tools() List[ExternalTool]:
	var out = List[ExternalTool]()

	for dir in [join([user_dir(), "extensions"]), join([project_dir(), "extensions"])]:
		entries := list(dir).to_optional()
		if entries.is_none(): continue

		for entry in entries.get([]):
			if not entry.name.ends_with(".json"): continue

			text := read_text(join([dir.clone(), entry.name.clone()]))
			if text.is_none(): continue

			doc := parse(text.get("")).to_optional()
			if doc.is_none(): continue

			d := doc.get(JsonValue.Null)
			command := d.get("command").get(JsonValue.Null).as_list().get([]).map(
				fn c: (c.as_string().get(""))
			)
			if command.is_empty(): continue

			out.append(
				ExternalTool(
					name: str_or(d, "name", ""),
					description: str_or(d, "description", ""),
					command: command,
					schema: d.get("parameters").get(
						JsonValue.Null
					).clone()
				)
			)

	return out

// Runs an external tool, passing the arguments as JSON on stdin.
export fn run_external(tool: ExternalTool, args: JsonValue) String!:
	input := try render(args)
	out := try run(
		tool.command[0], tool.command.drop(1),
		RunOptions(input: input.to_bytes(), timeout: none)
	).wait()
	text := "{out.stdout.decode_utf8().get("")}{out.stderr.decode_utf8().get("")}".trim()
	if out.exit_code != 0: return error(Error("{text}\n\nexit code {out.exit_code}"))

	return ok(text)
