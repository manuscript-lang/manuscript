// Compares the fact JSON of the C checker (`ms_check_dump STDLIB --facts FILE`) with
// the Rust checker's (`ms-tooling-dev facts FILE`) for one program.
//   ms run tools/ms/facts_diff.ms -- RUST.json C.json
//
// The entity keys, kinds and lines must be equal. Then each field in FIELDS is
// compared; a field joins FIELDS when the C checker's column for it exists. effects,
// reach and permits are compared only for entities the C checker marks effects_known.
// Not compared yet, and printed empty by the C writer: calls (the effect scan misses
// implicit close calls), external, error, scopes, result_ownership, passing modes,
// refs, `move` receivers (checker facts), imports and flows. The process fails when
// anything differs, and the output counts the entities and fields compared so a silent
// skip shows.
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
	if not got.effects_known: return ""

	// The C checker leaves these empty when it cannot see all of what the entity calls.
	if field == "effects" and want.effects != got.effects: return f"effects {want.effects} != {got.effects}"
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
