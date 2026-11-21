// Compares the fact JSON of the C checker (`ms_check_dump STDLIB --facts FILE`) with
// the Rust checker's (`ms-tooling-dev facts FILE`) for one program.
//   ms run tools/ms/facts_diff.ms -- RUST.json C.json
//
// The entity keys, kinds and lines must be equal. Then each field in FIELDS is
// compared; a field joins FIELDS when the C checker's column for it exists. effects,
// reach, permits and calls are compared only for entities the C checker marks
// effects_known. Not compared yet, and printed empty by the C writer: external, scopes,
// result_ownership, passing modes, refs, `move` receivers (checker facts), flows.
// Imports are compared per file. The process fails when anything differs, and the
// output counts the entities and fields compared so a silent skip shows.
import (
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",

	Fact, Facts, Slot from "./views.ms",
)

FIELDS := [
	"name", "slots", "result", "receiver", "tries", "effects", "reach", "permits"
]

fn slot_text(s: Slot) String: f"{s.name}:{s.ty}:{s.exclusive}"

fn mode_text(s: Slot) String: f"{s.name}:{s.mode}"

fn modes_text(slots: List[Slot]) String: slots.map(mode_text).join(", ")

fn slots_text(slots: List[Slot]) String: slots.map(slot_text).join(", ")

fn result_text(f: Fact) String:
	if r := f.result: return r.ty.clone()
	return "<none>"

// The difference of one field of one entity, or "".
fn field_diff(field: String, want: Fact, got: Fact) String:
	if field == "name" and want.name != got.name: return f"name {want.name} != {got.name}"
	if field == "slots" and slots_text(want.slots) != slots_text(got.slots): return f"slots [{slots_text(want.slots)}] != [{slots_text(got.slots)}]"
	if field == "result" and result_text(want) != result_text(got): return f"result {result_text(want)} != {result_text(got)}"

	// `move` versus `borrow` needs the checker's moving-parameter facts; only `var` is syntax.
	if field == "receiver" and (want.receiver == "var") != (got.receiver == "var"): return f"receiver {want.receiver} != {got.receiver}"
	if field == "tries" and want.tries != got.tries: return f"tries {want.tries} != {got.tries}"

	// The C writer types only functions; the other kinds print an empty type and error.
	if field == "ty" and want.kind == "fn" and want.ty != got.ty: return f"ty {want.ty} != {got.ty}"
	if field == "error" and want.kind == "fn" and want.error != got.error: return f"error {want.error} != {got.error}"

	// The ownership columns are the checker's only for a function its ownership walk
	// kept.
	if (
		field == "modes"
		and got.ownership_known
		and modes_text(want.slots) != modes_text(got.slots)
	): return f"modes [{modes_text(want.slots)}] != [{modes_text(got.slots)}]"
	if field == "scopes" and got.ownership_known and want.scopes != got.scopes: return f"scopes {want.scopes} != {got.scopes}"
	if (
		field == "result_ownership"
		and got.ownership_known
		and want.result_ownership != got.result_ownership
	): return f"result_ownership {want.result_ownership} != {got.result_ownership}"
	if field == "label" and want.label != got.label: return f"label {want.label} != {got.label}"
	if field == "first" and want.first != got.first: return f"first {want.first} != {got.first}"
	if field == "last" and want.last != got.last: return f"last {want.last} != {got.last}"
	if field == "exported" and want.exported != got.exported: return f"exported {want.exported} != {got.exported}"
	if not got.effects_known: return ""

	// The C checker leaves these empty when it cannot see all of what the entity calls.
	if field == "effects" and want.effects != got.effects: return f"effects {want.effects} != {got.effects}"
	if field == "calls" and want.calls != got.calls: return f"calls {want.calls} != {got.calls}"
	if field == "reach" and want.reach != got.reach: return f"reach {want.reach} != {got.reach}"
	if field == "permits" and want.permits != got.permits: return f"permits {want.permits} != {got.permits}"

	return ""

fn load(path: String) Facts!:
	return ok(parse[Facts](read_file(path).wait()?.decode_utf8().get_or(""))?)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn main() Void!:
	args := arguments()
	if args.length() != 2: return error(Error("usage: facts_diff.ms RUST.json C.json"))

	want := load(args[0])?
	got := load(args[1])?
	var out = ""
	var differ = 0
	var compared = 0
	var got_index = Map[String, Int]()
	for i in 0..got.entities.length(): got_index.add(got.entities[i].key.clone(), i)

	for w in want.entities:
		i := got_index.get_or(w.key, -1)

		if i < 0:
			out = out.concat(f"missing in C: {w.key}\n")
			differ += 1
			continue

		g := got.entities[i]
		compared += 1

		if g.kind != w.kind or g.line != w.line:
			out = out.concat(
				f"{w.key}: kind or line {w.kind}:{w.line} != {g.kind}:{g.line}\n"
			)
			differ += 1

		for field in FIELDS:
			text := field_diff(field, w, g)

			if not text.is_empty():
				out = out.concat(f"{w.key}: {text}\n")
				differ += 1

	for w in want.imports:
		var found = false

		for g in got.imports:
			if g.file == w.file:
				found = true

				want_paths := w.paths.join(",")
				got_paths := g.paths.join(",")

				if want_paths != got_paths:
					out = out.concat(
						f"imports of {w.file}: {want_paths} != {got_paths}\n"
					)
					differ += 1

		if not found:
			out = out.concat(f"imports of {w.file} missing in C\n")
			differ += 1

	var want_keys = Set[String]()
	for w in want.entities: want_keys.add(w.key.clone())

	for g in got.entities:
		if not want_keys.contains(g.key):
			out = out.concat(f"extra in C: {g.key}\n")
			differ += 1

	out = out.concat(
		f"{compared} entities compared, {FIELDS.length()} fields each, {differ} differences\n"
	)

	var stream = stdout()
	stream.write(out)?
	stream.flush()?
	if differ > 0: return error(Error("facts differ"))
