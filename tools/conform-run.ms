// The conformance corpus replayed against an ms binary, in Manuscript. This is the runner
// that replaces the Rust `ms-conform run`: it reads each fixture's recorded expectation
// (tests/conformance/fixtures/**/<name>.expected.json), observes the ms under test the way
// crates/ms-conform/src/observe.rs does, and counts the fixtures whose observation equals
// the recorded one. The frozen Rust runner stays as the cross-check until both give the
// same five counts (parse, check, run, test, commands).
//
// Phases implemented so far: parse. Recording, fuzz and harvest are not ported (#6224,
// #6225, #6226). MS names the ms under test (default target/release/ms).
// Usage: ms run tools/conform-run.ms -- [--phase parse] [fixture id substring ...]
// Prints `parse: passed/total` and one `FAIL <id>` line per difference.
import (
	Bytes from "@std/bytes.ms",
	JsonValue, parse, stringify from "@std/data/json.ms",
	arguments, working_directory from "@std/os/env.ms",
	GlobOptions,
	copy,
	create_directory,
	glob,
	read_file,
	temporary from "@std/os/fs.ms",
	CommandOutput, RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// One recorded fixture: its id (the path under the fixtures root without `.ms`), the source
// file and the recorded observation.
type Fixture:
	id: String
	source: String
	phase: String
	expected: JsonValue

fn text_of(data: Bytes) String:
	return data.decode_utf8().get_or("").clone()

fn member(value: JsonValue, key: String) JsonValue?:
	return value.get(key)

fn string_member(value: JsonValue, key: String) String:
	if found := value.get(key):
		return found.as_string().get_or("")
	return ""

// The fixtures of `phase` under `root`, in path order. A directory named `support` holds
// shared files, not fixtures.
fn fixtures(root: String, phase: String, filters: List[String]) List[Fixture]:
	var found = List[Fixture]()
	paths := glob(root, GlobOptions(patterns: ["**/*.expected.json"])).get_or([])
	for entry in paths:
		if entry.path.contains("/support/"): continue

		id := entry.path.slice(0, entry.path.length() - ".expected.json".length())
		if not selected(id, filters): continue

		text := text_of(read_file(f"{root}/{entry.path}").wait().get())
		document := parse(text).get()
		if string_member(document, "phase") != phase: continue

		expected := document.get("expected")
		if expected.is_none(): continue

		found.append(
			Fixture(
				id: id.clone(),
				source: f"{root}/{id}.ms",
				phase: phase.clone(),
				expected: expected.get().clone(),
			),
		)
	return found

fn selected(id: String, filters: List[String]) Bool:
	if filters.is_empty(): return true

	for filter in filters:
		if id.contains(filter): return true
	return false

// `text` with the work directory (as given and with forward slashes) as <DIR> and its
// parent as <SCRATCH>.
fn normalize_text(text: String, work: String) String:
	var out = text.replace(work, "<DIR>").replace(work.replace("\\", "/"), "<DIR>")
	parent_end := parent_length(work)
	if parent_end > 0:
		parent := work.slice(0, parent_end)
		out = out.replace(parent, "<SCRATCH>").replace(parent.replace("\\", "/"), "<SCRATCH>")
	return out

fn parent_length(path: String) Int:
	var at = path.length()
	while at > 0:
		at -= 1
		last := path.slice(at, at + 1)
		if last == "/" or last == "\\": return at
	return 0

// Every string of `value` normalized, and the `subcode` members the frozen corpus never
// recorded dropped.
fn normalized(value: JsonValue, work: String) JsonValue:
	match value:
		StringValue(text): return JsonValue.StringValue(normalize_text(text, work))
		ArrayValue(items):
			var out = List[JsonValue]()
			for item in items: out.append(normalized(item, work))
			return JsonValue.ArrayValue(out)
		ObjectValue(fields):
			var out = Map[String, JsonValue]()
			for field in fields.entries():
				if field.key == "subcode": continue
				out.add(field.key.clone(), normalized(field.value, work))
			return JsonValue.ObjectValue(out)
		_: return value.clone()

fn invoke(ms: String, args: List[String], work: String, limit: Int) CommandOutput:
	return run(
		ms.clone(),
		args,
		RunOptions(cwd: work.clone(), timeout: seconds(limit)),
	).wait().get()

// The text of `source` below its `// conform:` header lines.
fn without_header(source: String) String:
	var skip = 0
	for line in source.split("\n"):
		if not line.starts_with("// conform:"): break

		skip += line.length() + 1
	if skip > source.length(): return ""

	return source.slice(skip, source.length())

// What the parse phase observes of one fixture: the parse diagnostics of `fmt --check
// --json` (`fmt` parses without loading the standard library) and the formatted source.
fn observe_parse(ms: String, fx: Fixture) JsonValue:
	scratch := temporary("ms-conform-").get()
	work := f"{scratch.path()}/w"
	create_directory(work.clone()).get()
	name := fx.id.slice(parent_length(fx.id) + 1, fx.id.length()) + ".ms"
	copy(fx.source.clone(), f"{work}/{name}").get()

	checked := invoke(ms, ["fmt", name.clone(), "--check", "--json"], work, 30)
	var diagnostics = List[JsonValue]()
	var raw = JsonValue.Null
	match parse(text_of(checked.stdout)):
		ok(document):
			report := normalized(document, work)
			if listed := report.get("diagnostics"):
				for item in listed.as_list().get_or([]):
					if string_member(item, "phase") == "parse": diagnostics.append(item.clone())
		error(cause):
			var broken = Map[String, JsonValue]()
			broken.add("unparsable_json", JsonValue.StringValue(f"{cause}"))
			broken.add("stdout", JsonValue.StringValue(normalize_text(text_of(checked.stdout), work)))
			raw = JsonValue.ObjectValue(broken)

	var fields = Map[String, JsonValue]()
	fields.add("diagnostics", JsonValue.ArrayValue(diagnostics))
	if not raw.is_null(): fields.add("raw", raw)

	formatted := invoke(ms, ["fmt", name.clone()], work, 30)
	if formatted.exit_code == 0:
		after := text_of(read_file(f"{work}/{name}").wait().get())
		fields.add("fmt", JsonValue.StringValue(without_header(after)))
	else:
		fields.add("fmt", JsonValue.Null)
		fields.add("fmt_exit_code", JsonValue.NumberValue(f"{formatted.exit_code}"))
	return JsonValue.ObjectValue(fields)

fn same(left: JsonValue, right: JsonValue) Bool:
	return stringify(left).get() == stringify(right).get()

fn main() Int:
	root := working_directory().get()
	var phase = "parse"
	var filters = List[String]()
	var words = List[String]()
	for word in arguments(): words.append(word.clone())

	var at = 0
	while at < words.length():
		if words[at] == "--phase":
			at += 1
			phase = words[at].clone()
		else: filters.append(words[at].clone())
		at += 1

	if phase != "parse":
		print(f"conform-run: phase {phase} is not ported yet")
		return 64

	ms := tool_ms(root.clone())
	var total = 0
	var passed = 0
	for fx in fixtures(f"{root}/tests/conformance/fixtures", phase, filters):
		total += 1
		observed := observe_parse(ms, fx)
		if same(fx.expected, observed): passed += 1
		else: print(f"FAIL {fx.id}")

	print(f"{phase}: {passed}/{total}")
	if passed != total: return 1

	return 0
