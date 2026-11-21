// The standard-library reference generator: Markdown pages, the plain Markdown and
// structured JSON downloads, from an API model. Port of
// crates/ms-tooling/src/guide/docgen.rs (`site_files`).
//
// Until the C checker can build the model, it is read from a JSON file the Rust
// `ms-tooling` example `api_model` prints (every field of an `ApiModule`, including the
// source excerpts the public JSON leaves out).
//   ms run tools/ms/docgen.ms -- MODEL.json OUTDIR
// writes `OUTDIR/documentation/standard-library/reference/...` and
// `OUTDIR/website/static/stdlib.*`.
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	create_directory, read_file, write_file from "@std/os/fs.ms",

	run_tool from "./cli.ms",
)

export type Member:
	name: String
	kind: String
	signature: String
	doc: String
	contract: String
	legacy_contract: String

export type Declaration:
	declaration: String
	name: String
	doc: String
	effects: List[String]
	kind: String
	opaque: Bool
	type: String
	type_parameters: List[String]
	fields: List[String]
	cases: List[String]
	operations: List[String]
	members: List[Member]
	implements: List[String]
	implementation_declarations: List[String]

export type Module:
	path: String
	declarations: List[Declaration]

type Model:
	modules: List[Module]

// ---- Markdown ----

fn declaration_kind(kind: String) String:
	if kind == "fn": return "Function"
	if kind == "constant": return "Constant"
	if kind == "alternative": return "Enum"
	if kind == "interface": return "Interface"
	if kind == "type": return "Type"
	if kind == "native": return "Native type"

	return kind.clone()

fn debug_quote(text: String) String: f"\"{text}\""

// One module as Markdown; `for_site` tags each heading with its kind.
export fn render(module: Module, for_site: Bool) String:
	path := module.path
	var b = f"# {path}\n\n"

	if path == "prelude": b = b.concat(
		"Names available in every module; no import required.\n\n"
	)
	else if path == "@std/core.ms":
		b = b.concat(
			"`Error`, `Optional`, `Result`, `Equal`, `Comparable`, and `Hashable` are prelude declarations; explicit imports of them are rejected.\n\n"
		)
		b = b.concat(
			f"Import other names with `import Name from {debug_quote(path)}`.\n\n"
		)
	else if path == "@std/collections/collections.ms":
		b = b.concat(
			"`List`, `Map`, `Set`, `ListEntry`, and `MapEntry` are prelude declarations; explicit imports of them are rejected.\n\n"
		)
		b = b.concat(
			f"Import other names with `import Name from {debug_quote(path)}`.\n\n"
		)
	else if path.starts_with("@std/"): b = b.concat(
		f"Import each required symbol with `import Name from {debug_quote(path)}`.\n\n"
	)

	for d in module.declarations:
		var kind = declaration_kind(d.kind)

		// Native types with receiver signatures share the checker's interface
		// representation, but their source declaration remains a type.
		if d.kind == "interface" and d.declaration.starts_with("type "): kind = "Native type"

		if for_site: b = b.concat(
			f"## {d.name} \{data-api-kind={debug_quote(kind)}\}\n\n"
		)
		else: b = b.concat(f"## {d.name}\n\n**{kind}**\n\n")

		if d.declaration.is_empty():
			b = b.concat("This member uses compiler-defined call behavior.\n\n")
			continue

		if not d.doc.is_empty(): b = b.concat(f"{d.doc}\n\n")
		b = b.concat(f"```manuscript\n{d.declaration}```\n\n")
		for implementation in d.implementation_declarations: b = b.concat(
			f"```manuscript\n{implementation}```\n\n"
		)

		var legacy_headings = Set[String]()

		for member in d.members:
			if member.doc.trim().is_empty(): continue

			name := if member.contract.is_empty(): f"{d.name}.{member.name}" else: f"{d.name}.{member.contract}.{member.name}"

			if for_site and not member.legacy_contract.is_empty():
				legacy := f"{d.name}.{member.legacy_contract}.{member.name}"

				if not legacy_headings.contains(legacy):
					legacy_headings.add(legacy.clone())
					b = b.concat(
						f"\{\{< api-legacy-anchor {debug_quote(legacy)} >\}\}\n\n"
					)

			b = b.concat(
				f"### {name}\n\n{member.doc}\n\n```manuscript\n{member.signature}\n```\n\n"
			)

	return b

// ---- JSON ----

fn hex4(value: Int) String:
	digits := "0123456789abcdef"
	var out = ""

	for shift in [12, 8, 4, 0]:
		var divisor = 1
		for _step in 0..shift / 4: divisor *= 16
		out = out.concat(digits.slice(value / divisor % 16, value / divisor % 16 + 1))

	return out

// A JSON string as Go's encoding/json writes it (`<`, `>`, `&`, U+2028 and U+2029
// escaped).
export fn json_string(text: String) String:
	var out = "\""

	for ch in text.chars():
		if ch == "\"": out = out.concat("\\\"")
		else if ch == "\\": out = out.concat("\\\\")
		else if ch == "\n": out = out.concat("\\n")
		else if ch == "\r": out = out.concat("\\r")
		else if ch == "\t": out = out.concat("\\t")
		else:
			scalar := ch.scalar_at(0)

			if scalar == 8: out = out.concat("\\b")
			else if scalar == 12: out = out.concat("\\f")
			else if (
				scalar == 60
				or scalar == 62
				or scalar == 38
				or scalar == 8232
				or scalar == 8233
				or scalar < 32
			): out = out.concat(f"\\u{hex4(scalar)}")
			else: out = out.concat(ch)

	return out.concat("\"")

export fn indent(depth: Int) String: "  ".repeat(depth)

// A JSON array of strings at `depth`, or `[]`.
export fn string_array(items: List[String], depth: Int) String:
	if items.is_empty(): return "[]"

	var out = "["

	for i in 0..items.length():
		if i > 0: out = out.concat(",")
		out = out.concat(f"\n{indent(depth + 1)}{json_string(items[i])}")

	return out.concat(f"\n{indent(depth)}]")

fn member_json(m: Member, depth: Int) String:
	pad := indent(depth + 1)
	var out = f"\{\n{pad}\"name\": {json_string(m.name)},\n{pad}\"kind\": {json_string(m.kind)},\n{pad}\"signature\": {json_string(m.signature)},\n{pad}\"doc\": {json_string(m.doc)}"
	if not m.contract.is_empty(): out = out.concat(
		f",\n{pad}\"contract\": {json_string(m.contract)}"
	)
	return out.concat(f"\n{indent(depth)}\}")

fn optional_list(key: String, items: List[String], pad: String, depth: Int) String:
	if items.is_empty(): return ""
	return f",\n{pad}\"{key}\": {string_array(items, depth + 1)}"

fn declaration_json(d: Declaration, depth: Int) String:
	pad := indent(depth + 1)
	var out = f"\{\n{pad}\"name\": {json_string(d.name)}"
	if not d.doc.is_empty(): out = out.concat(f",\n{pad}\"doc\": {json_string(d.doc)}")
	out = out.concat(f",\n{pad}\"kind\": {json_string(d.kind)}")
	if d.opaque: out = out.concat(f",\n{pad}\"opaque\": true")
	out = out.concat(f",\n{pad}\"type\": {json_string(d.type)}")
	out = out.concat(optional_list("type_parameters", d.type_parameters, pad, depth))
	out = out.concat(optional_list("fields", d.fields, pad, depth))
	out = out.concat(optional_list("cases", d.cases, pad, depth))
	out = out.concat(optional_list("operations", d.operations, pad, depth))

	if not d.members.is_empty():
		var members = "["

		for i in 0..d.members.length():
			if i > 0: members = members.concat(",")
			members = members.concat(
				f"\n{indent(depth + 2)}{member_json(d.members[i], depth + 2)}"
			)

		out = out.concat(f",\n{pad}\"members\": {members}\n{pad}]")

	if not d.implements.is_empty(): out = out.concat(
		f",\n{pad}\"implements\": {string_array(d.implements, depth + 1)}"
	)
	return out.concat(f"\n{indent(depth)}\}")

// The structured API snapshot, as `website/static/stdlib.json` writes it.
export fn to_json(modules: List[Module]) String:
	var out = "{\n  \"format\": 1,\n  \"modules\": ["

	for i in 0..modules.length():
		if i > 0: out = out.concat(",")

		m := modules[i]
		var declarations = "["

		for j in 0..m.declarations.length():
			if j > 0: declarations = declarations.concat(",")
			declarations = declarations.concat(
				f"\n        {declaration_json(m.declarations[j], 4)}"
			)

		if m.declarations.is_empty(): declarations = "[]"
		else: declarations = declarations.concat("\n      ]")

		out = out.concat(
			f"\n    \{\n      \"path\": {json_string(m.path)},\n      \"declarations\": {declarations}\n    \}"
		)

	return out.concat("\n  ]\n}\n")

// ---- site files ----

fn module_stem(file: String) String:
	path := file.cut_prefix("@std/").get_or(file).cut_suffix(".ms").get_or(
		file.cut_prefix("@std/").get_or(file)
	)
	if path == "test/test": return "test"
	if path == "test/bench": return "bench"

	if parts := path.split_once("/"):
		for package in ["collections", "concurrency", "data", "io", "math", "net", "os"]:
			if parts.before == package: return parts.after.clone()
	return path

fn last_component(path: String) String:
	if slash := path.last_index_of("/"): return path.slice(slash + 1, path.length())
	return path.clone()

// Every generated file by path, in the order they are written.
export fn site_files(modules: List[Module]) Map[String, String]:
	var files = Map[String, String]()
	var index = "+++\ntitle = \"API reference\"\nweight = 2\n+++\n\n# Standard library API reference\n\nLook up types, functions, and import paths in the bundled standard library. Browse the source file tree below; prelude collects names available without an import. These declarations are generated from public source modules and omit implementation bodies. For usage, see the [Promises](../../core-language/concurrency/promises.md) and [Streams and pipes](../../core-language/concurrency/streams.md) topic guides.\n\n[Plain Markdown](/stdlib.md) · [Structured JSON](/stdlib.json) · [LLM index](/llms.txt)\n\n"
	var full = "# Manuscript implemented standard library\n\nGenerated from the bundled standard-library declarations.\n\n"
	for module in modules: full = full.concat(render(module, false))

	var directories = Map[String, String]()
	var order = List[String]()

	for module in modules:
		source_path := module.path.cut_prefix("@std/").get_or(module.path)
		path := source_path.cut_suffix(".ms").get_or(source_path)
		title := last_component(source_path)
		var source = f"stdlib/{source_path}"

		if path == "prelude": source = "stdlib/core/core.ms"
		else if (
			source_path == "core.ms"
			or source_path == "intrinsics.ms"
			or source_path == "string.ms"
		): source = f"stdlib/core/{source_path}"

		old := module_stem(module.path).replace("/", "-")
		aliases := if old != path: f"aliases = [\"/standard-library/reference/{old}/\"]\n" else: ""
		files.add(
			f"documentation/standard-library/reference/{source_path}.md",
			f"+++\ntitle = {debug_quote(title)}\nslug = {debug_quote(last_component(path))}\nedit_source = {debug_quote(source)}\n{aliases}+++\n\n{render(module, true)}",
		)

		var parent = ""
		parts := path.split("/")

		for part in parts.slice(0, parts.length() - 1).get_or([]):
			directory := if parent.is_empty(): part.clone() else: f"{parent}/{part}"

			if not directories.contains(directory):
				link := f"- [{part}/]({part}/_index.md)\n"

				if parent.is_empty(): index = index.concat(link)
				else: directories.add(
					parent.clone(),
					directories.get_or(parent, "").concat(link),
				)

				directories.add(
					directory.clone(),
					f"+++\ntitle = {debug_quote(part)}\nurl = \"/standard-library/reference/tree/{directory}/\"\n+++\n\n# {directory}/\n\n",
				)
				order.append(directory.clone())

			parent = directory.clone()

		link := f"- [{title}]({title}.md)\n"

		if parent.is_empty(): index = index.concat(link)
		else: directories.add(
			parent.clone(),
			directories.get_or(parent, "").concat(link),
		)

	for directory in order:
		files.add(
			f"documentation/standard-library/reference/{directory}/_index.md",
			directories.get_or(directory, ""),
		)
	files.add("documentation/standard-library/reference/_index.md", index)
	files.add("website/static/stdlib.md", full)
	files.add("website/static/stdlib.json", to_json(modules))
	return files

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
fn show(m: Matches) Void!:
	text := read_file(m.string("model")).wait()?.decode_utf8().get_or("")
	model := parse[Model](text)?
	files := site_files(model.modules)

	for path in files.keys():
		target := f"{m.string("outdir")}/{path}"
		if slash := target.last_index_of("/"): create_directory(
			target.slice(0, slash),
			recursive: true,
		)?
		write_file(target, files.get_or(path, "").to_bytes()).wait()?

fn docgen_tool() Command:
	return Command(
		name: "docgen.ms",
		about: "Write the standard-library reference pages from the model",
		args: [
			Arg("model", help: "The model JSON"),
			Arg("outdir", help: "Where the files go"),
		],
	)

fn main() Int:
	return run_tool(docgen_tool(), show)
