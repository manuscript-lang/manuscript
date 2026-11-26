// ms: allow_effect std.console.write
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Standard-library API reference (`make docs`): reads the snapshot `ms dev doc` prints
// and writes
//   - the book's reference pages under `<artifacts>/documentation/standard-library/reference/`,
//   - the downloads `<static>/stdlib.md` and `<static>/stdlib.json`,
//   - with `--coverage <file>`, the description inventory as JSON.
// Every declaration and member needs a description that passes the structural checks,
// except the keys listed in tools/description-backlog.json; a problem prints as
// `API description: ...`. MS names the ms to run. Usage:
//   ms run tools/docgen.ms [-- --check] [--downloads] [--coverage FILE] [--artifacts DIR] [--static DIR]
// `--check` validates without writing; `--downloads` writes only the two downloads.
import (
	parse, stringify from "@std/data/json.ms",
	arguments, working_directory from "@std/os/env.ms",
	create_directory, exists, read_file, remove, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	note, tool_ms from "./lib.ms",
)

type Member {
	name, kind, signature String
	doc, contract String = ""
}

type Declaration {
	name, kind, declaration String
	doc String = ""
	opaque Bool = false
	members List[Member] = []
}

type Module {
	path String
	declarations List[Declaration]
}

type Snapshot {
	format Int
	modules List[Module]
}

type Policy {
	format Int
	backlog List[String] = []
}

// ---- rendering ----

fn kind_label(d Declaration) String {
	// A native type with receiver signatures keeps its source kind, a type.
	if d.kind == "interface" and d.declaration.starts_with(
		"type "
	) { return "Native type" }
	if d.kind == "fn" { return "Function" }
	if d.kind == "constant" { return "Constant" }
	if d.kind == "alternative" { return "Enum" }
	if d.kind == "interface" { return "Interface" }
	if d.kind == "type" { return "Type" }
	if d.kind == "native" { return "Native type" }

	return d.kind.clone()
}

fn quote(text String) String {
	return stringify(text).get_or("\"\"")
}

fn introduction(path String) String {
	if path == "prelude" { return "Names available in every module; no import required.\n\n" }

	import_line := f"Import other names with `import Name from {quote(path.clone())}`.\n\n"
	if path == "@std/core.ms" { return f"`Error`, `Optional`, `Result`, `Equal`, `Comparable`, and `Hashable` are prelude declarations; explicit imports of them are rejected.\n\n{import_line}" }
	if path == "@std/collections/collections.ms" { return f"`List`, `Map`, `Set`, `ListEntry`, and `MapEntry` are prelude declarations; explicit imports of them are rejected.\n\n{import_line}" }
	if path.starts_with(
		"@std/"
	) { return f"Import each required symbol with `import Name from {quote(path.clone())}`.\n\n" }

	return ""
}

fn member_title(d Declaration, m Member) String {
	if m.contract == "" { return f"{d.name}.{m.name}" }
	return f"{d.name}.{m.contract}.{m.name}"
}

// One module as Markdown; `site` tags each heading with its kind for the book.
fn render(module Module, site Bool) String {
	var b = f"# {module.path}\n\n{introduction(module.path.clone())}"

	for d in module.declarations {
		kind := kind_label(d.clone())

		if site {
			b += f"## {d.name} \{data-api-kind={quote(kind)}\}\n\n"
		} else {
			b += f"## {d.name}\n\n**{kind}**\n\n"
		}

		if d.declaration == "" {
			b += "This member uses compiler-defined call behavior.\n\n"
			continue
		}

		if d.doc != "" { b += f"{d.doc}\n\n" }
		b += f"```manuscript\n{d.declaration}```\n\n"

		for m in d.members {
			if m.doc.trim() == "" { continue }

			b += f"### {member_title(d.clone(), m.clone())}\n\n{m.doc}\n\n```manuscript\n{m.signature}\n```\n\n"
		}
	}

	return b
}

fn full_markdown(modules List[Module]) String {
	var b = "# Manuscript implemented standard library\n\nGenerated from the bundled standard-library declarations.\n\n"
	for module in modules {
		b += render(module.clone(), false)
	}
	return b
}

// ---- the book's tree ----

// `core.ms` and its siblings live in src/stdlib/core; everything else mirrors its import path.
fn source_of(path, source_path String) String {
	if path == "prelude" { return "src/stdlib/core/core.ms" }
	if (
		source_path == "core.ms"
		or source_path == "intrinsics.ms"
		or source_path == "string.ms"
	) { return f"src/stdlib/core/{source_path}" }

	return f"src/stdlib/{source_path}"
}

packages := ["collections", "concurrency", "data", "io", "math", "net", "os"]

// The dashed name the page had before the reference mirrored source paths, for its
// redirect.
fn old_stem(module_path String) String {
	var path = module_path.clone()
	if path.starts_with("@std/") {
		path = path.slice(5, path.length()).clone()
	}
	if path.ends_with(".ms") {
		path = path.slice(0, path.length() - 3).clone()
	}
	if path == "test/test" { return "test" }
	if path == "test/bench" { return "bench" }

	cut := path.split_once("/")
	if cut != null {
		if packages.contains(cut.before) {
			return cut.after.replace("/", "-")
		}
	}
	return path.replace("/", "-")
}

fn last_part(path String) String {
	return (path.split("/").last() or "").clone()
}

type Tree {
	files Map[String, String]
	order List[String]
	// The directory index pages, keyed by directory, in creation order.
	directories Map[String, String]
	directory_order List[String]
	index String
}

// Adds a page, taking the two collections it changes rather than the whole tree so a
// caller can walk another part of the tree meanwhile.
fn put_page(
	var files Map[String, String],
	var order List[String],
	path,
	body String,
) Void {
	if not files.contains(path) { order.append(path.clone()) }
	files[path.clone()] = body.clone()
}

fn var Tree.link(parent, line String) Void {
	if parent == "" {
		self.index += line
		return
	}

	existing := self.directories.get_or(parent, "").clone()
	self.directories[parent.clone()] = f"{existing}{line}"
}

fn site_tree(modules List[Module]) Tree {
	var tree = Tree(
		files: Map[String, String](),
		order: [],
		directories: Map[String, String](),
		directory_order: [],
		index: "+++\ntitle = \"API reference\"\nweight = 2\n+++\n\n# Standard library API reference\n\nLook up types, functions, and import paths in the bundled standard library. Browse the source file tree below; prelude collects names available without an import. These declarations are generated from public source modules and omit implementation bodies. For usage, see the [Promises](../../core-language/concurrency/promises.md) and [Streams and pipes](../../core-language/concurrency/streams.md) topic guides.\n\n[Plain Markdown](/stdlib.md) · [Structured JSON](/stdlib.json) · [LLM index](/llms.txt)\n\n",
	)
	base := "documentation/standard-library/reference"

	for module in modules {
		var source_path = module.path.clone()
		if source_path.starts_with("@std/") {
			source_path = source_path.slice(5, source_path.length()).clone()
		}

		var path = source_path.clone()
		if path.ends_with(".ms") {
			path = path.slice(0, path.length() - 3).clone()
		}

		title := last_part(source_path.clone())
		source := source_of(module.path.clone(), source_path.clone())
		old := old_stem(module.path.clone())
		aliases := if old != path { f"aliases = [\"/standard-library/reference/{old}/\"]\n" } else { "" }
		put_page(
			tree.files,
			tree.order,
			f"{base}/{source_path}.md",
			f"+++\ntitle = {quote(title.clone())}\nslug = {quote(last_part(path.clone()))}\nedit_source = {quote(source)}\n{aliases}+++\n\n{render(module.clone(), true)}",
		)

		parts := path.split("/")
		var parent = ""

		for at in 0..parts.length() - 1 {
			part := parts[at].clone()
			var directory = part.clone()
			if parent != "" { directory = f"{parent}/{part}" }

			if not tree.directories.contains(directory) {
				tree.link(parent.clone(), f"- [{part}/]({part}/_index.md)\n")
				tree.directories[directory.clone()] = f"+++\ntitle = {quote(part.clone())}\nurl = \"/standard-library/reference/tree/{directory}/\"\n+++\n\n# {directory}/\n\n"
				tree.directory_order.append(directory.clone())
			}

			parent = directory
		}

		tree.link(parent.clone(), f"- [{title}]({title}.md)\n")
	}

	for directory in tree.directory_order {
		put_page(
			tree.files,
			tree.order,
			f"{base}/{directory}/_index.md",
			tree.directories.get_or(directory, "").clone(),
		)
	}
	put_page(tree.files, tree.order, f"{base}/_index.md", tree.index.clone())
	return tree
}

// ---- descriptions ----

type Entry {
	module, declaration, kind, name, contract String
	described, qualified Bool
	problem String
}

placeholders := [
	"todo", "tbd", "fixme", "placeholder", "undocumented", "description goes here",
	"documentation goes here"
]
ignored_words := "a an the this that these those it its s of for to from with without and or in on at by as is are be can may will field member method function operation case type declaration public exported native standard api value data object property describes describing represents returns holds provides gets sets has about information description documentation named called contains containing stores stored storing reports whether behavior behaviour contract fn record interface int int64 float float64 bool void never string bytes optional result list map set payload"

fn is_upper(c String) Bool {
	return c >= "A" and c <= "Z"
}

fn is_lower(c String) Bool {
	return c >= "a" and c <= "z"
}

fn is_word(c String) Bool {
	return (
		is_upper(c.clone())
		or is_lower(c.clone())
		or (c >= "0" and c <= "9")
		or c > "~"
	)
}

// Lowercase words of prose, camel-case names and snake_case names.
fn description_words(text String) List[String] {
	var words = List[String]()
	var current = ""
	var previous = ""

	for c in text.chars() {
		if is_upper(c.clone()) and is_lower(previous.clone()) and current != "" {
			words.append(current.clone())
			current = ""
		}

		if is_word(c.clone()) {
			current += c.lower()
		} else if current != "" {
			words.append(current.clone())
			current = ""
		}

		previous = c.clone()
	}

	if current != "" { words.append(current.clone()) }
	return words
}

fn description_problem(entry Entry, doc String) String {
	raw := doc.trim()
	text := raw.lower()
	if text == "" { return "missing description" }

	var trimmed = text.clone()
	while (
		trimmed.starts_with("#")
		or trimmed.starts_with(" ")
		or trimmed.starts_with("`")
		or trimmed.starts_with("*")
	) {
		trimmed = trimmed.slice(1, trimmed.length()).clone()
	}
	for placeholder in placeholders {
		if trimmed.starts_with(
			placeholder
		) { return "placeholder description" }
	}

	words := description_words(raw.clone())
	if words.length() < 4 { return "description is too terse to state a contract" }

	var skipped = Set[String]()
	for word in description_words(f"{entry.name} {entry.declaration}") {
		skipped.add(word.clone())
	}
	for word in ignored_words.split(" ") {
		skipped.add(word.clone())
	}
	for word in words {
		if not skipped.contains(
			word
		) { return "" }
	}
	return "description only restates the API name or kind"
}

fn entry_of(module, declaration, kind, name, contract, doc String) Entry {
	draft := Entry(
		module: module.clone(),
		declaration: declaration.clone(),
		kind: kind.clone(),
		name: name.clone(),
		contract: contract.clone(),
		described: doc.trim() != "",
		qualified: false,
		problem: "",
	)
	problem := description_problem(draft.clone(), doc)
	return Entry(
		module: draft.module.clone(),
		declaration: draft.declaration.clone(),
		kind: draft.kind.clone(),
		name: draft.name.clone(),
		contract: draft.contract.clone(),
		described: draft.described,
		qualified: problem == "",
		problem: problem,
	)
}

fn inventory(modules List[Module]) List[Entry] {
	var entries = List[Entry]()

	for module in modules {
		for d in module.declarations {
			entries.append(
				entry_of(
					module.path.clone(),
					d.name.clone(),
					"declaration",
					d.name.clone(),
					"",
					d.doc.clone(),
				)
			)
			for m in d.members {
				entries.append(
					entry_of(
						module.path.clone(),
						d.name.clone(),
						m.kind.clone(),
						m.name.clone(),
						m.contract.clone(),
						m.doc.clone(),
					)
				)
			}
		}
	}

	return entries
}

fn description_key(e Entry) String {
	return [
		e.module.clone(),
		e.declaration.clone(),
		e.kind.clone(),
		e.name.clone(),
		e.contract.clone(),
	].join("|")
}

// Problems of the entries against the recorded backlog: a new gap fails, a described or
// removed entry must leave the backlog.
fn check_descriptions(entries List[Entry], backlog List[String]) List[String] {
	var problems = List[String]()
	var listed = Set[String]()

	for key in backlog {
		if listed.contains(
			key
		) { problems.append(f"{key}: duplicate description backlog entry") }
		listed.add(key.clone())
	}

	var seen = Set[String]()

	for e in entries {
		key := description_key(e.clone())
		seen.add(key.clone())
		if listed.contains(key) and e.described {
			problems.append(
				f"{key}: description exists; remove the stale backlog entry"
			)
		}
		if e.qualified or (not e.described and listed.contains(key)) { continue }

		problems.append(
			f"{key}: {e.problem}; describe observable behavior, units, defaults, errors or ownership"
		)
	}

	for key in backlog {
		if not seen.contains(key) {
			problems.append(
				f"{key}: API no longer exists; remove the stale backlog entry"
			)
		}
	}
	problems.sort()
	return problems
}

// ---- coverage JSON ----

fn flag(value Bool) String {
	if value { return "true" }
	return "false"
}

fn coverage_json(entries List[Entry]) String {
	var declarations = 0
	var described_declarations = 0
	var qualified_declarations = 0
	var members = 0
	var described_members = 0
	var qualified_members = 0
	var prelude = false
	var rows = List[String]()

	for e in entries {
		if e.module == "prelude" { prelude = true }

		if e.kind == "declaration" {
			declarations += 1
			if e.described { described_declarations += 1 }
			if e.qualified { qualified_declarations += 1 }
		} else {
			members += 1
			if e.described { described_members += 1 }
			if e.qualified { qualified_members += 1 }
		}

		var row = f"    \{\n      \"module\": {quote(e.module.clone())},\n      \"declaration\": {quote(e.declaration.clone())},\n      \"kind\": {quote(e.kind.clone())},\n      \"name\": {quote(e.name.clone())}"
		if e.contract != "" { row += f",\n      \"contract\": {quote(e.contract.clone())}" }
		row += f",\n      \"described\": {flag(e.described)},\n      \"qualified\": {flag(e.qualified)}"
		if e.problem != "" { row += f",\n      \"problem\": {quote(e.problem.clone())}" }
		rows.append(f"{row}\n    \}")
	}

	listing := rows.join(",\n")
	return f"\{\n  \"format\": 1,\n  \"includes_prelude_aliases\": {flag(prelude)},\n  \"declarations\": {declarations},\n  \"described_declarations\": {described_declarations},\n  \"members\": {members},\n  \"described_members\": {described_members},\n  \"qualified_declarations\": {qualified_declarations},\n  \"qualified_members\": {qualified_members},\n  \"entries\": [\n{listing}\n  ]\n\}\n"
}

// ---- files ----

fn parent_of(path String) String {
	parts := path.split("/")
	if parts.length() < 2 { return "" }

	return parts.slice(0, parts.length() - 1).get().join("/")
}

fn write_text(path, text String) Void! {
	folder := parent_of(path.clone())
	if folder != "" { create_directory(folder, recursive: true)? }
	write_file(path, text, replace: true).wait()?
	return ok(void)
}

type Options {
	check, downloads Bool = false
	coverage String = ""
	artifacts String = ".artifacts/docs"
	static_dir String = "website/static"
}

fn options_of(words List[String]) Options! {
	var o = Options()
	var at = 0

	while at < words.length() {
		word := words[at].trim_start_chars("-")

		if word == "check" {
			o.check = true
		} else if word == "downloads" {
			o.downloads = true
		} else if word == "coverage" or word == "artifacts" or word == "static" {
			at += 1
			if at >= words.length() {
				return error(Error(f"flag needs an argument: --{word}"))
			}

			if word == "coverage" {
				o.coverage = words[at].clone()
			} else if word == "artifacts" {
				o.artifacts = words[at].clone()
			} else {
				o.static_dir = words[at].clone()
			}
		} else {
			return error(Error(f"flag provided but not defined: --{word}"))
		}

		at += 1
	}

	return ok(o)
}

fn text_of(path String) String! {
	return ok((read_file(path).wait()?.decode_utf8() or "").clone())
}

fn generate(ms String, o Options) Void! {
	ran := run(ms.clone(), ["dev", "doc"]).wait()?
	if ran.exit_code != 0 { return error(Error(f"{ms} doc failed")) }

	snapshot_text := (ran.stdout.decode_utf8() or "").clone()
	snapshot := parse[Snapshot](snapshot_text.clone())?
	modules := snapshot.modules.clone()
	entries := inventory(modules.clone())
	var described_declarations = 0
	var described_members = 0
	var declarations = 0
	var members = 0
	var qualified_declarations = 0
	var qualified_members = 0

	for e in entries {
		if e.kind == "declaration" {
			declarations += 1
			if e.described { described_declarations += 1 }
			if e.qualified { qualified_declarations += 1 }
		} else {
			members += 1
			if e.described { described_members += 1 }
			if e.qualified { qualified_members += 1 }
		}
	}

	note(
		f"API descriptions: {described_declarations}/{declarations} declarations, {described_members}/{members} members (including prelude aliases)"
	)
	note(
		f"Description quality: {qualified_declarations}/{declarations} declarations, {qualified_members}/{members} members pass structural checks; semantic review remains required"
	)
	if o.coverage != "" { write_text(o.coverage.clone(), coverage_json(entries.clone()))? }

	policy := parse[Policy](text_of("tools/description-backlog.json")?)?
	if policy.format != 1 {
		return error(Error(f"unsupported description policy format {policy.format}"))
	}

	problems := check_descriptions(entries.clone(), policy.backlog.clone())

	if not problems.is_empty() {
		for problem in problems {
			note(f"API description: {problem}")
		}
		return error(Error(""))
	}

	if o.check { return ok(void) }

	// All book Markdown is disposable: rebuild its tree to retire removed routes.
	if not o.downloads and exists(o.artifacts.clone()).get_or(false) {
		remove(o.artifacts.clone(), recursive: true)?
	}

	// A report inside the retired tree is written again.
	if o.coverage != "" and not exists(o.coverage.clone()).get_or(false) {
		write_text(o.coverage.clone(), coverage_json(entries.clone()))?
	}

	if not o.downloads {
		tree := site_tree(modules.clone())
		for path in tree.order {
			write_text(f"{o.artifacts}/{path}", tree.files.get_or(path, "").clone())?
		}
	}

	write_text(f"{o.static_dir}/stdlib.md", full_markdown(modules.clone()))?
	write_text(f"{o.static_dir}/stdlib.json", snapshot_text)?
	return ok(void)
}

fn main() Int {
	root := working_directory().get()
	parsed := options_of(arguments())

	if parsed.is_error() {
		note(parsed.err().message)
		return 2
	}

	result := generate(tool_ms(root), parsed.get())

	if result.is_error() {
		why := result.err().message.clone()
		if why != "" { note(why) }
		return 1
	}

	return 0
}
