// Session persistence: one JSONL file per conversation under ~/.pi/agent/sessions/<cwd>/.
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
	header.add("version", num(1))
	header.add("cwd", str(try working_directory()))

	text := try line("session", header)
	try append_file(path, "{text}\n").wait()
	return ok(Session(id: id, path: path))

// Appends one message entry.
export fn append(session: Session, message: JsonValue) Unit!:
	var entry = Map[String, JsonValue]()
	entry.add("message", message.clone())

	text := try line("message", entry)
	return append_file(session.path, "{text}\n").wait()

// Reads the messages back, skipping the header and unknown entries.
export fn load(path: String) List[JsonValue]!:
	data := try read_file(path).wait()
	text := data.decode_utf8().get("")
	var out = List[JsonValue]()

	for raw in text.split("\n"):
		if raw.trim().is_empty(): continue

		entry := try parse(raw)
		if str_or(entry, "type", "") != "message": continue

		if message := entry.get("message"): out.append(message.clone())

	return ok(out)

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
