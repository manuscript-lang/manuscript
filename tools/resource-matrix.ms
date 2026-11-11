// Resource ownership matrix (`make resource-matrix`): generates one program for each combination of a
// standard operation that takes, returns or discards a one-owner resource, a call form (direct call, or a
// method value called later) and an argument form (a temporary, or a named variable), then checks each one.
// A combination the checker rejects is fine: the rule is that anything `ms check` accepts must lower, run and
// close every resource it made exactly once. The oracle needs no expected output per case: `mk` prints
// `made-N`, `close` prints `closed-N`, and the two must match at exit, in Debug and Release.
// A new standard operation that stores, returns or discards a `T` belongs in OPERATIONS below.
// MS names the ms that runs the programs (default target/release/ms).
// Usage: ms run tools/resource-matrix.ms [-- name-filter]
import (
	JsonValue, parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments, working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	tool_ms from "./lib.ms",
)

HEADER := """
import Closeable, print from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!:
        print("closed-\{self.id\}")

fn saw(m: Marker) Unit:
    print("saw-\{m.id\}")

fn saw_opt(m: Marker?) Unit:
    print("saw-\{m.is_some()\}")

fn mk(id: Int) Marker:
    print("made-\{id\}")
    return Marker(id)

fn run() Unit:
"""
FOOTER := """
fn main() Unit:
    run()
"""

// One standard operation: the receiver it runs on, its method, its arguments (`@V@` is the resource
// argument) and what to do with a result.
type Operation:
	name: String
	setup: String
	receiver: String
	method: String
	arguments: String
	binds: String
	uses: String

fn op(
	name: String,
	setup: String,
	receiver: String,
	method: String,
	arguments: String,
	binds: String,
	uses: String
) Operation:
	return Operation(name, setup, receiver, method, arguments, binds, uses)

fn list_setup() String: return "var items = [mk(1)]"

fn map_setup() String: return "var items = Map[Int, Marker]()\n    items.add(1, mk(1))"

fn optional_setup(present: Bool) String:
	if present: return "held: Marker? := mk(1)"
	return "held: Marker? := none"

fn result_setup(good: Bool) String:
	if good: return "held: Marker!Error := ok(mk(1))"
	return "held: Marker!Error := error(Error(\"x\"))"

fn operations() List[Operation]:
	return [
		op("list_append", list_setup(), "items", "append", "@V@", "", ""),
		op("list_prepend", list_setup(), "items", "prepend", "@V@", "", ""),
		op("list_insert", list_setup(), "items", "insert", "0, @V@", "", ""),
		op("list_set", list_setup(), "items", "set", "0, @V@", "", ""),
		op(
			"list_replace", list_setup(), "items", "replace", "0, @V@", "r := ",
			"saw(r)"
		),
		op("list_pop", list_setup(), "items", "pop", "", "r := ", "saw_opt(r)"),
		op("list_remove", list_setup(), "items", "remove", "0", "", ""),
		op(
			"list_get", list_setup(), "items", "get", "0, @V@", "r := ", "saw(r)"
		),
		op(
			"result_map", result_setup(true), "held", "map", "fn m: m.id", "r := ",
			"print(\"\{r.is_ok()\}\")"
		),
		op("map_add", map_setup(), "items", "add", "1, @V@", "", ""),
		op(
			"map_get", map_setup(), "items", "get", "1", "r := ",
			"print(\"\{r.is_some()\}\")"
		),
		op(
			"optional_or_else", optional_setup(false), "held", "or_else", "fn: @V@",
			"r := ", "saw_opt(r)"
		),
		op(
			"result_err", result_setup(false), "held", "err", "", "r := ",
			"print(r.message)"
		),
		op(
			"optional_get_present", optional_setup(true), "held", "get", "@V@", "r := ",
			"saw(r)"
		),
		op(
			"optional_get_absent", optional_setup(false), "held", "get", "@V@", "r := ",
			"saw(r)"
		),
		op(
			"result_get_ok", result_setup(true), "held", "get", "@V@", "r := ", "saw(r)"
		),
		op(
			"result_get_error", result_setup(false), "held", "get", "@V@", "r := ",
			"saw(r)"
		),
		op(
			"result_to_optional", result_setup(true), "held", "to_optional", "",
			"r := ", "saw_opt(r)"
		),
		op(
			"result_error_ok", result_setup(true), "held", "error", "", "r := ",
			"print(\"\{r.is_some()\}\")"
		),
		op(
			"result_error_failed", result_setup(false), "held", "error", "", "r := ",
			"print(\"\{r.is_some()\}\")"
		)
	]

// Standard operations that mention a type parameter and need no matrix row, each with the reason. An
// operation that returns, stores or discards a `T` does not belong here: add a row to `operations()`.
fn exempt() List[String]:
	return [
		"List.max: returns a copy of a Comparable and Clonable element, so a resource cannot reach it",
		"List.min: returns a copy of a Comparable and Clonable element, so a resource cannot reach it",
		"Map.map: the callback borrows each entry and builds new values",
		"Map.map_keys: declared U: Clonable, so a resource value cannot reach it",
		"Map.find: declared U: Clonable, so a resource value cannot reach it",
		"Map.keys: copies Hashable keys into a new list",
		"Set.add: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.clear: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.clone: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.contains: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.difference: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.filter: gap: the matrix has no Hashable resource, so sets are not exercised yet",
		"Set.find: gap: the matrix has no Hashable resource, so sets are not exercised yet"
	]

// The type parameters of the standard type `name`, as the declarations write them.
fn type_parameters(name: String) List[String]:
	if name == "Map": return ["T", "U"]
	if name == "Result": return ["T", "E"]

	return ["T"]

// The words of a signature, split at the punctuation of types.
fn words(text: String) List[String]:
	var spaced = text.clone()
	for mark in ["(", ")", "[", "]", ",", ":", "?", "!", "=", "&", "<", ">", ";"]:
		spaced = spaced.replace(mark, " ")

	var found = List[String]()
	for word in spaced.split(" "):
		if word != "": found.append(word.clone())
	return found

// Whether the declaration `signature` changes its receiver, or takes or returns one of `names` outside a callback.
fn mentions_parameter(signature: String, names: List[String]) Bool:
	if signature.contains("var fn"): return true

	parts := signature.split("fn ")
	if parts.length() < 2: return false

	var depth = 0
	var outside = ""
	var result = ""

	for c in parts[1].chars():
		if c == "(": depth += 1
		if depth == 0 and c != ")": result = "{result}{c}"
		if depth == 1 and c != "(": outside = "{outside}{c}"
		if c == ")": depth -= 1

	for word in words("{outside} {result}"):
		if names.contains(word): return true
	return false

fn field(entry: JsonValue, key: String) String:
	if value := entry.get(key): return value.as_string().get("")
	return ""

// Every `Type.operation` of the standard type whose declaration mentions a type parameter.
fn declared_operations(ms: String, name: String) List[String]!:
	ran := try run(ms, ["search_symbol", "prelude.{name}", "--json", "--limit", "300"]).wait()
	page := try parse(ran.stdout.decode_utf8().get(""))
	var found = List[String]()
	names := type_parameters(name.clone())

	if all := page.get("matches"):
		for entry in all.as_list().get([]):
			if field(entry, "kind") != "operation": continue
			if not mentions_parameter(field(entry, "type"), names.clone()): continue

			last := field(entry, "name").split(".")
			found.append("{name}.{last[last.length() - 1]}")

	return ok(found)

// How many standard operations that mention a type parameter have neither a row nor a reason.
fn uncovered(ms: String, ops: List[Operation]) Int:
	var known = List[String]()
	kinds := ["list", "map", "set", "optional", "result"]
	titles := ["List", "Map", "Set", "Optional", "Result"]
	for o in ops:
		for i in 0..kinds.length():
			if o.name.starts_with("{kinds[i]}_"): known.append("{titles[i]}.{o.method}")
	for line in exempt(): known.append(line.split(":")[0].clone())

	var missing = 0

	for title in titles:
		listed := declared_operations(ms.clone(), title.clone())

		if listed.is_error():
			missing += 1
			(
				stdout()
				.write(
					"coverage: could not list {title}: {listed.err().message}\n"
				)
				.get()
			)
			continue

		for name in listed.get():
			if known.contains(name): continue

			missing += 1
			(
				stdout()
				.write(
					"coverage: {name} mentions a type parameter but has no row in operations() and no reason in exempt()\n"
				)
				.get()
			)

	return missing

// The program for `o`, called as `call_form` (`direct` or `bound`), with its resource argument made as `arg_form`.
fn program(o: Operation, call_form: String, arg_form: String) String:
	var lines = [o.setup.clone()]
	var argument = ""

	if o.arguments.contains("@V@"):
		var value = "mk(2)"

		if arg_form == "named":
			lines.append("v := mk(2)")
			value = "v"

		argument = o.arguments.replace("@V@", value)
	else:
		argument = o.arguments.clone()

	if call_form == "bound":
		lines.append("f := {o.receiver}.{o.method}")
		lines.append("{o.binds}f({argument})")
	else:
		lines.append("{o.binds}{o.receiver}.{o.method}({argument})")

	if o.uses != "": lines.append(o.uses.clone())

	var body = ""
	for line in lines: body = "{body}    {line}\n"
	return "{HEADER}\n{body}\n{FOOTER}\n"

// How many times `prefix` + `id` appears as a line, for each id made.
fn count(lines: List[String], prefix: String) Map[String, Int]:
	var counts = Map[String, Int]()

	for line in lines:
		if not line.starts_with(prefix): continue

		key := line.trim()
		counts.add(key.clone(), counts.get_or(key.clone(), 0) + 1)

	return counts

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root)
	scratch := temporary("ms-matrix-").get()
	var filter = ""
	for a in arguments(): filter = a.clone()

	var checked = 0
	var rejected = 0
	var failures = uncovered(ms.clone(), operations())

	for o in operations():
		for call_form in ["direct", "bound"]:
			for arg_form in ["temporary", "named"]:
				name := "{o.name}_{call_form}_{arg_form}"
				if filter != "" and not name.contains(filter): continue

				file := "{scratch.path()}/{name}.ms"
				write_file(file, program(o, call_form, arg_form)).wait().get()

				verdict := run(ms.clone(), ["check", file.clone()]).wait()

				if verdict.is_error() or verdict.get().exit_code != 0:
					rejected += 1

					why := verdict.get().stderr.decode_utf8().get("")

					// Only a checker rule may reject a combination; a program that does not parse is this tool's bug.
					if why.contains(": parse:"):
						failures += 1
						(
							stdout()
							.write(
								"generated: {name} does not parse: {why}\n"
							)
							.get()
						)
					else if filter != "":
						print("rejected {name}: {why}")

					continue

				for build in ["debug", "release"]:
					checked += 1

					ran := run(
						ms.clone(),
						[
							"run", file.clone(), "--build-type", build.clone()
						]
					).wait()

					if ran.is_error():
						failures += 1
						(
							stdout()
							.write(
								"run: {name} ({build}) could not run {ms}\n"
							)
							.get()
						)
						continue

					child := ran.get()
					lines := child.stdout.decode_utf8().get("").split("\n")

					if child.exit_code != 0:
						failures += 1

						why := child.stderr.decode_utf8().get("")
						(
							stdout()
							.write(
								"exit: {name} ({build}) passed `ms check` but failed: {why}\n"
							)
							.get()
						)
						continue

					var made = List[String]()
					var closed = List[String]()

					for line in lines:
						if line.starts_with("made-"): made.append(
							line.slice(
								5, line.length()
							).get("")
						)
						if line.starts_with("closed-"):
							closed.append(line.slice(7, line.length()).get(""))

					made_counts := count(lines, "made-")
					var wrong = made.length() != closed.length()

					for id in made:
						want := made_counts.get_or("made-{id}", 0)
						var have = 0
						for c in closed:
							if c == id: have += 1
						if want != have: wrong = true

					if wrong:
						failures += 1
						(
							stdout()
							.write(
								"ownership: {name} ({build}) made {made.join(",")} and closed {closed.join(",")}; each resource must close once ({file})\n"
							)
							.get()
						)

	(
		stdout()
		.write(
			"matrix: {checked} runs, {rejected} combinations rejected by the checker, {failures} failing\n"
		)
		.get()
	)

	if checked == 0:
		print("no combination ran")
		return 1

	if failures > 0: return 1

	return 0
