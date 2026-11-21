// The standard-call table and module map of the agent skill, rendered from the standard
// library's declarations. Port of crates/ms-tooling/src/guide/skill_calls.rs. The API
// model is read from the JSON the Rust `api_model` example prints (the same file
// `docgen.ms` reads) until the C checker can build it.
//   ms run tools/ms/skill_calls.ms --link target/c-tool/libmstool.a -- update MODEL.json SKILL_DIR
//   ms run tools/ms/skill_calls.ms --link target/c-tool/libmstool.a -- check MODEL.json SKILL_DIR
// `SKILL_DIR` holds `references/standard-calls.md` and `references/standard-modules.md`;
// `update` rewrites their generated blocks, `check` fails when one is stale.
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	read_file, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	run_program from "./cli.ms",
	Declaration, Module from "./docgen.ms",
	keywords from "./syntax.ms",
)

CALLS_START := "<!-- calls:start -->"
CALLS_END := "<!-- calls:end -->"
MODULES_START := "<!-- modules:start -->"
MODULES_END := "<!-- modules:end -->"
// Prelude types in table order.
TYPES := ["String", "List", "Map", "Set", "Optional", "Result", "Int", "Float"]

type Model:
	modules: List[Module]

// `fn(A, B) R` as `(A, B) R`: the call shape without the keyword.
fn shape(signature: String) String:
	return signature.cut_prefix("fn").get_or(signature)

// One operation: its name (with type parameters) and its signature.
type Operation:
	name: String
	signature: String

// Splits `name[U: Bound]: signature` at the colon after the name, not the one in a
// bound.
fn split_operation(operation: String) Operation?:
	var depth = 0

	for at in 0..operation.length():
		c := operation.slice(at, at + 1)
		rest := operation.slice(at + 1, operation.length())

		if c == "[": depth += 1
		else if c == "]" and depth > 0: depth -= 1
		else if c == ":" and depth == 0 and rest.starts_with(" "): return Operation(
			name: operation.slice(0, at),
			signature: operation.slice(at + 2, operation.length()),
		)

	return none

fn find_declaration(prelude: Module, name: String) Declaration?:
	for d in prelude.declarations:
		if d.name == name: return d.clone()
	return none

// The calls of one prelude type: each name once, every signature of it, sorted by name.
fn type_line(d: Declaration) String:
	var by_name = Map[String, List[String]]()

	for operation in d.operations:
		pair := split_operation(operation)
		if pair.is_none(): continue

		name := pair.get().name.split("[")[0].clone()
		signature := pair.get().signature.clone()
		var seen = by_name.get_or(name, [])
		if not seen.contains(signature): seen.append(signature)
		by_name.add(name, seen)

	var calls = List[String]()

	for name in by_name.keys().sorted():
		var shapes = List[String]()
		for signature in by_name.get_or(name, []): shapes.append(
			f"{name}{shape(signature)}"
		)
		calls.append(shapes.join(" | "))

	if calls.is_empty(): return ""

	return f"- {d.name}: {calls.join("; ")}\n"

// The generated block: every call of each prelude type, then the reserved words.
export fn render_calls(modules: List[Module]) String:
	var out = f"{CALLS_START}\n"

	for module in modules:
		if module.path != "prelude": continue

		for type_name in TYPES:
			d := find_declaration(module, type_name)
			if d.is_some(): out = out.concat(type_line(d.get()))

	out = out.concat("\n")
	out = out.concat(
		f"Reserved words are never names (a variable called `type` or `test` fails): {keywords().join(" ")}.\n"
	)
	return out.concat(f"{CALLS_END}\n")

// Every standard module with the names it exports, so an agent finds the import it
// needs.
export fn render_modules(modules: List[Module]) String:
	var out = f"{MODULES_START}\n"

	for module in modules:
		if not module.path.starts_with("@std/") or module.path.contains("/internal/"): continue

		names := module.declarations.map(fn d: d.name.clone())
		if names.is_empty(): continue

		out = out.concat(f"- `{module.path}`: {names.join(", ")}\n")

	return out.concat(f"{MODULES_END}\n")

// The block between `start` and `end` as it stands in `page`, with its trailing
// newline.
fn block_between(page: String, start: String, end: String) String?:
	from := page.index_of(start)
	to := page.index_of(end)
	if from.is_none() or to.is_none(): return none

	return f"{page.slice(from.get(), to.get() + end.length())}\n"

// `page` with the block between `start` and `end` replaced by `block`.
fn splice_between(page: String, start: String, end: String, block: String) String?:
	from := page.index_of(start)
	to := page.index_of(end)
	if from.is_none() or to.is_none(): return none

	stop := to.get() + end.length()
	rest := page.slice(stop, page.length())
	tail := rest.cut_prefix("\n").get_or(rest)
	return f"{page.slice(0, from.get())}{block}{tail}"

// One page of the skill: its path, generated block markers and the block rendered now.
type Target:
	path: String
	start: String
	end: String
	block: String

fn targets(directory: String, modules: List[Module]) List[Target]:
	return [
		Target(
			path: f"{directory}/references/standard-calls.md",
			start: CALLS_START,
			end: CALLS_END,
			block: render_calls(modules),
		),
		Target(
			path: f"{directory}/references/standard-modules.md",
			start: MODULES_START,
			end: MODULES_END,
			block: render_modules(modules),
		),
	]

fn skill_calls_tool() Command:
	return Command(
		name: "skill_calls.ms",
		about: "Keep the call tables of the agent skill pages in step with the model",
		children: [
			Command(
				name: "update",
				about: "Rewrite the stale blocks",
				args: [
					Arg("model", help: "The model JSON"),
					Arg("skill", help: "The skill directory"),
				],
			),
			Command(
				name: "check",
				about: "Fail when a block is stale",
				args: [
					Arg("model", help: "The model JSON"),
					Arg("skill", help: "The skill directory"),
				],
			),
		],
	)

// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
fn sync(m: Matches) Int!:
	update := m.path[1] == "update"
	model := parse[Model](read_file(m.string("model")).wait()?.decode_utf8().get_or(""))?
	var stale = false

	for target in targets(m.string("skill"), model.modules):
		page := read_file(target.path).wait()?.decode_utf8().get_or("")
		updated := splice_between(page, target.start, target.end, target.block)

		if updated.is_none():
			print(f"{target.path} has no {target.start} and {target.end} markers")
			return ok(2)

		if (
			block_between(page, target.start, target.end) != block_between(
				updated.get(),
				target.start,
				target.end,
			)
		):
			stale = true
			print(f"{target.path}: stale")

		if update: write_file(target.path, updated.get(), replace: true).wait()?

	if not update and stale: return ok(1)

	return ok(0)

fn main() Int:
	return run_program(skill_calls_tool(), sync)

test "a block is replaced between its markers":
	page := "head\n<!-- calls:start -->\nold\n<!-- calls:end -->\ntail\n"
	updated := splice_between(
		page,
		CALLS_START,
		CALLS_END,
		"<!-- calls:start -->\nnew\n<!-- calls:end -->\n",
	)
	(
		updated.get() | expect_equal(
			expected: "head\n<!-- calls:start -->\nnew\n<!-- calls:end -->\ntail\n"
		)?
	)

test "an operation splits at the colon after its name":
	(
		split_operation("map[U: Bound]: fn(T) U").get().name
		| expect_equal(expected: "map[U: Bound]")?
	)
	(
		split_operation(
			"map[U: Bound]: fn(T) U"
		).get().signature | expect_equal(expected: "fn(T) U")?
	)
