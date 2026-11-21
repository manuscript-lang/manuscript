// The checker's per-node facts for one module, read from `ms_check_dump STDLIB --nodes
// FILE` (compiler/tests/nodes-diff.sh describes the columns). A
// node is listed only when the C body pass typed it, so a missing node means "unknown",
// never "not that type".
import (
	parse from "@std/data/json.ms",
	SpawnOptions, Stdio, run from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
)

type Node:
	id: Int
	kind: String
	arg: String = ""

type Document:
	nodes: List[Node]

export type Facts:
	// The type kind of the expression with this tree node id: Optional, Result, List,
	// Map, Set, Bytes, Int, Float, Bool, String, Void, Promise or Other.
	kinds: Map[Int, String] = Map[Int, String]()
	// The kind of the first type argument (a Result's payload, a List's element), for
	// the nodes that have one.
	args: Map[Int, String] = Map[Int, String]()

// The facts in the JSON document `text`; none when it is not one.
export fn read_facts(text: String) Facts?:
	document := parse[Document](text)
	if document.is_error(): return none

	var facts = Facts()

	for node in document.get().nodes:
		facts.kinds.add(node.id, node.kind.clone())
		if not node.arg.is_empty(): facts.args.add(node.id, node.arg.clone())

	return facts

// The type kind of node `id`, or "" when the checker did not type it.
export fn kind_of(facts: Facts, id: Int) String:
	return facts.kinds.get_or(id, "")

// The kind of the first type argument of node `id`, or "" when it has none or the
// checker did not type it.
export fn arg_of(facts: Facts, id: Int) String:
	return facts.args.get_or(id, "")

// The facts of `path` from the checker dump program `dump`, with the standard library
// in
// `stdlib`; none when the program cannot run or prints no document.
// ms: allow_effect std.process.run
export fn load_facts(dump: String, stdlib: String, path: String) Facts?:
	out := run(dump.clone(), [stdlib.clone(), "--nodes", path.clone()]).wait()
	if out.is_error(): return none

	return read_facts(out.get().stdout.decode_utf8().get_or(""))

test "the kind of the first type argument is read by id":
	facts := read_facts(
		"{\"nodes\": [{\"id\": 4, \"kind\": \"Result\", \"arg\": \"Void\"}, {\"id\": 5, \"kind\": \"Int\"}]}"
	).get()
	arg_of(facts, 4) | expect_equal(expected: "Void")?
	arg_of(facts, 5) | expect_equal(expected: "")?

test "node kinds are read by id":
	facts := read_facts("{\"nodes\": [{\"id\": 4, \"kind\": \"Optional\"}]}").get()
	kind_of(facts, 4) | expect_equal(expected: "Optional")?
	kind_of(facts, 5) | expect_equal(expected: "")?
