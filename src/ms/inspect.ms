// The default `ms diagram` renderings (the call graph as text and as Mermaid) over the
// `ms inspect` document. Port of `Inspection::mermaid`, `diagram_ascii` and the standard-library
// filter of crates/ms-cli/src/engine/tooling.rs (`diagram`); the Rust command is the
// oracle.
//
// Until the C checker prints the document, it is read from the JSON file `ms inspect`
// prints.
//   ms run src/ms/inspect.ms -- INSPECT.json [ascii|mermaid]
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	sha256 from "@std/crypto/crypto.ms",
	hex_encode from "@std/data/encoding.ms",
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",

	run_tool from "./cli.ms",
)

export type Span:
	file: String
	line: Int

export type Entity:
	id: String
	kind: String
	name: String
	span: Span

export type Call:
	owner: String
	target: String
	kind: String

export type Inspection:
	entities: List[Entity]
	calls: List[Call]

// An entity ID written for people: `@std/time.ms#fn#monotonic` reads
// `@std/time.ms::monotonic`; text that is not a `file#kind#name` ID is returned unchanged.
fn readable_id(id: String) String:
	parts := id.split("#")
	if parts.length() < 3: return id.clone()

	file := parts[0]
	name := parts.drop(2).join("#")
	if file.is_empty() or parts[1].is_empty() or name.is_empty(): return id.clone()

	return f"{file.cut_suffix("+source").get_or(file)}::{name}"

// Application structure only: standard-library entities and the calls they own are
// dropped, and a standard method target is named by receiver and method, not its source
// offset.
export fn application_only(inspection: Inspection) Inspection:
	var std_methods = Map[String, String]()
	for e in inspection.entities:
		if e.span.file.starts_with("@std/") and e.kind == "method": std_methods.add(
			e.id.clone(),
			e.name.clone(),
		)

	var calls = List[Call]()

	for c in inspection.calls:
		if c.owner.starts_with("@std/"): continue

		calls.append(
			Call(
				owner: c.owner.clone(),
				target: std_methods.get_or(c.target, c.target),
				kind: c.kind.clone(),
			)
		)

	return Inspection(
		entities: inspection.entities.filter(
			fn e: not e.span.file.starts_with("@std/")
		),
		calls: calls,
	)

fn label_of(labels: Map[String, String], id: String) String:
	return labels.get(id).get_or(readable_id(id))

fn entity_labels(inspection: Inspection) Map[String, String]:
	var labels = Map[String, String]()
	for e in inspection.entities: labels.add(e.id.clone(), f"{e.span.file}::{e.name}")
	return labels

// The call graph as an outline: owners in the inspection's order, each followed by its
// distinct callees (ordered by label, then kind) with a count.
export fn diagram_ascii(inspection: Inspection) String:
	labels := entity_labels(inspection)
	var edges = Map[String, Map[String, Int]]()

	for c in inspection.calls:
		// The key sorts by target label, then kind; the unit separator cannot occur in
		// either.
		var owner_edges = edges.get_or(c.owner, Map[String, Int]())
		key := f"{label_of(labels, c.target)}\u{1f}{c.kind}"
		owner_edges.add(key.clone(), owner_edges.get_or(key, 0) + 1)
		edges.add(c.owner.clone(), owner_edges)

	var out = "CALL GRAPH\n"

	for e in inspection.entities:
		out = out.concat(f"{label_of(labels, e.id)} [{e.kind}]\n")

		owner_edges := edges.get_or(e.id, Map[String, Int]())

		for key in owner_edges.keys().sorted():
			parts := key.split("\u{1f}")
			n := owner_edges.get_or(key, 0)
			count := if n > 1: f" x{n}" else: ""
			out = out.concat(f"  -> {parts[0]} ({parts[1]}){count}\n")

	return out

fn mermaid_label(label: String) String:
	return label.replace("&", "&amp;").replace("\"", "&quot;").replace(
		"<",
		"&lt;",
	).replace(">", "&gt;").replace("\n", " ")

fn node_key(id: String) String: f"n{hex_encode(sha256(id.to_bytes())).slice(0, 16)}"

fn declare(var out: String, var seen: Set[String], id: String, label: String) String:
	key := node_key(id)

	if not seen.contains(id):
		seen.add(id.clone())
		out = out.concat(f"    {key}[\"{mermaid_label(label)}\"]\n")

	return key

// The mermaid call graph.
export fn diagram_mermaid(inspection: Inspection) String:
	var out = "flowchart TD\n"
	var seen = Set[String]()
	for e in inspection.entities: void declare(
		out,
		seen,
		e.id,
		f"{e.span.file}::{e.name}",
	)

	for c in inspection.calls:
		owner := declare(out, seen, c.owner, c.owner)
		target := declare(out, seen, c.target, readable_id(c.target))
		out = out.concat(f"    {owner} -->|{c.kind}| {target}\n")

	return out

fn inspect_tool() Command:
	return Command(
		name: "inspect.ms",
		about: "Draw the call graph of an `ms inspect` document",
		args: [
			Arg("document", help: "The `ms inspect` JSON"),
			Arg(
				"format",
				required: false,
				help: "ascii (default) or mermaid",
			),
		],
	)

// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn show(m: Matches) Void!:
	document := parse[Inspection](
		read_file(m.string("document")).wait()?.decode_utf8().get_or("")
	)?
	inspection := application_only(document)
	var out = stdout()

	if m.string_or_none("format").get_or("ascii") == "mermaid": out.write(
		diagram_mermaid(inspection)
	)?
	else: out.write(diagram_ascii(inspection))?

	out.flush()?
	return ok()

fn main() Int:
	return run_tool(inspect_tool(), show)
