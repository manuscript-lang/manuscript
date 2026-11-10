// Session persistence: a JSONL tree per conversation under ~/.pi/agent/sessions/<cwd>/.
// Each entry has an id and the id of its parent, so a fork is just a new child of an earlier entry.
// A compaction entry stands for everything before it: the summary replaces the older history.
import (
	JsonValue, parse from "@std/data/json.ms",
	append_file, create_directory, list, read_file, stat from "@std/os/fs.ms",
	home_directory, working_directory from "@std/os/env.ms",
	join from "@std/os/path.ms",
	now from "@std/time.ms",
	uuid_v7 from "@std/data/uuid.ms",
	str, num, obj, render, str_or from "./jsonx.ms",
)

export type Session:
	id: String
	path: String

export type Entry:
	id: String
	// Parent entry id; empty for a root.
	parent: String
	// "message" or "compaction".
	kind: String
	message: JsonValue
	summary: String

// Directory holding sessions for the working directory: "/a/b" becomes "--a-b--".
export fn session_dir() String!:
	cwd := try working_directory()
	slug := cwd.trim_start_chars("/").replace("/", "-").replace(":", "-")
	home := try home_directory()
	return ok(join([home, ".pi", "agent", "sessions", "--{slug}--"]))

fn line(kind: String, fields: Map[String, JsonValue]) String!:
	var record = Map[String, JsonValue]()
	record.add("type", str(kind))
	record.add("timestamp", str(now().to_string()))
	for entry in fields.entries(): record.add(entry.key.clone(), entry.value.clone())
	return render(obj(record))

// Creates a new session file with its header line.
export fn create() Session!:
	dir := try session_dir()
	try create_directory(dir, recursive: true)

	id := try uuid_v7()
	path := join([dir, "{now().unix_seconds()}_{id}.jsonl"])
	var header = Map[String, JsonValue]()
	header.add("id", str(id))
	header.add("version", num(2))
	header.add("cwd", str(try working_directory()))

	text := try line("session", header)
	try append_file(path, "{text}\n").wait()
	return ok(Session(id: id, path: path))

fn short_id() String!:
	id := try uuid_v7()
	return ok(id.take(8) + id.drop(24).take(4))

fn write_entry(
	session: Session,
	kind: String,
	parent: String,
	fields: Map[String, JsonValue]
) String!:
	id := try short_id()
	var all = fields.clone()
	all.add("id", str(id))
	all.add("parentId", str(parent))

	text := try line(kind, all)
	try append_file(session.path, "{text}\n").wait()
	return ok(id)

// Appends a message as a child of `parent`; returns the new entry id.
export fn append(session: Session, parent: String, message: JsonValue) String!:
	var fields = Map[String, JsonValue]()
	fields.add("message", message.clone())
	return write_entry(session, "message", parent, fields)

// Appends a compaction entry holding `summary`; later history starts from it.
export fn append_compaction(session: Session, parent: String, summary: String) String!:
	var fields = Map[String, JsonValue]()
	fields.add("summary", str(summary))
	return write_entry(session, "compaction", parent, fields)

// Reads every entry in file order. Entries from the first version of the format (no ids) are chained in order.
export fn entries(path: String) List[Entry]!:
	data := try read_file(path).wait()
	text := data.decode_utf8().get("")
	var out = List[Entry]()
	var previous = ""

	for raw in text.split("\n"):
		if raw.trim().is_empty(): continue

		doc := try parse(raw)
		kind := str_or(doc, "type", "")
		if kind != "message" and kind != "compaction": continue

		id := str_or(doc, "id", "legacy-{out.length()}")
		parent := str_or(doc, "parentId", previous)
		message := doc.get("message").get(JsonValue.Null).clone()
		out.append(
			Entry(
				id: id.clone(), parent: parent, kind: kind, message: message,
				summary: str_or(doc, "summary", "")
			)
		)
		previous = id

	return ok(out)

fn find(all: List[Entry], id: String) Int?:
	return all.find_index(fn e: e.id == id)

// The id of the newest entry in the file, or "" for an empty session.
export fn last_id(all: List[Entry]) String:
	if all.is_empty(): return ""

	return all[all.length() - 1].id.clone()

fn summary_message(summary: String) JsonValue:
	var block = Map[String, JsonValue]()
	block.add("type", str("text"))
	block.add(
		"text",
		str(
			"The conversation so far was compacted. Summary of what happened:\n\n{summary}"
		)
	)

	var m = Map[String, JsonValue]()
	m.add("role", str("user"))
	m.add("content", JsonValue.ArrayValue([obj(block)]))
	return obj(m)

// The messages on the path from the root (or the latest compaction) to `leaf`.
export fn branch(all: List[Entry], leaf: String) List[JsonValue]:
	var reversed = List[JsonValue]()
	var at = leaf.clone()

	while not at.is_empty():
		index := find(all, at)
		if index.is_none(): break

		entry := all[index.get(0)]

		if entry.kind == "compaction":
			reversed.append(summary_message(entry.summary))
			break

		reversed.append(entry.message.clone())
		at = entry.parent.clone()

	var out = List[JsonValue]()
	var i = reversed.length() - 1

	while i >= 0:
		out.append(reversed[i].clone())
		i -= 1

	return out

fn preview(message: JsonValue) String:
	role := str_or(message, "role", "")
	blocks := message.get("content").get(JsonValue.Null).as_list().get([])

	for block in blocks:
		kind := str_or(block, "type", "")
		if kind == "text": return "{role}: {str_or(block, "text", "").replace("\n", " ").take(60)}"
		if kind == "tool_use": return "{role}: [{str_or(block, "name", "")}]"
		if kind == "tool_result": return "tool result"

	return role

// One display line per entry on the path to `leaf`, then its siblings' branches, indented by depth.
export fn tree(all: List[Entry], leaf: String) List[String]:
	var lines = List[String]()

	for entry in all:
		var depth = 0
		var at = entry.parent.clone()

		while not at.is_empty():
			depth += 1

			parent := find(all, at)
			if parent.is_none(): break

			at = all[parent.get(0)].parent.clone()

		label := if entry.kind == "compaction": "[compaction]" else: preview(
			entry.message
		)
		marker := if entry.id == leaf: "*" else: " "
		lines.append(
			"{marker} {entry.id} {" ".repeat(if depth > 20: 20 else: depth).get("")}{label}"
		)

	return lines

// Opens an existing session by file path.
export fn open_existing(path: String) Session!:
	_info := try stat(path)
	text := read_file(path).wait()
	var id = ""

	if data := text.to_optional():
		first := data.decode_utf8().get("").split("\n").get(0, "")
		if header := parse(first).to_optional(): id = str_or(header, "id", "")

	return ok(Session(id: id, path: path.clone()))

// Newest session file for the working directory.
export fn latest() String?:
	dir := session_dir().to_optional()
	if dir.is_none(): return none

	names := list(dir.get("")).to_optional()
	if names.is_none(): return none

	var files = names.get([]).filter(fn e: e.name.ends_with(".jsonl")).map(
		fn e: (e.name.clone())
	)
	if files.is_empty(): return none

	files.sort()
	return join([dir.get(""), files.last().get("")])
