// The lint rules about calls on a value whose type matters: `length()` compared with
// zero (MSL118), `get(i)` on a list (MSL119), a map `get` chained with `get_or`
// (MSL120), a Result `get` as a statement (MSL129, MSL130), a printed Result (MSL131),
// a `slice` with a fallback (MSL132), a Void value bound or printed (MSL134) and
// `to_string()` on Bytes (MSL135), a promise dropped as a statement (MSL115) a map entry rebuilt from its own lookup (MSL127) and a `while true` loop that never waits (MSL111). Each reports only what the checker's facts prove, so
// a node the checker did not type yields no finding.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Facts, arg_of, kind_of, read_facts from "./facts.ms",
	Finding, finding, with_fix from "./finding.ms",
	first_offset, last_offset, span from "./spans.ms",
)

// Binary operators as the syntax table numbers them.
OP_OR := 0
OP_AND := 1
OP_EQ := 2
OP_NE := 3
OP_GT := 5
// The compound assignments that stand for a binary operator (`+` is 8 ... `%` is 12).
OPERATOR_UPDATES := {8: "+=", 9: "-=", 10: "*=", 11: "/=", 12: "%="}

// Everything a rule reads: the tree, the checker facts, the source and the findings.
type Scan:
	tree: Syntax
	facts: Facts
	source: Bytes
	file: String
	call: Int
	member: Int
	number: Int
	binary: Int
	name: Int
	call_stmt: Int
	branch: Int
	loop: Int
	ret: Int
	bind: Int
	pattern: Int
	absent: Int

fn scan(tree: Syntax, facts: Facts, source: Bytes, file: String) Scan:
	return Scan(
		tree: tree,
		facts: facts,
		source: source,
		file: file.clone(),
		call: node_kind("Call"),
		member: node_kind("Member"),
		number: node_kind("Number"),
		binary: node_kind("Binary"),
		name: node_kind("Name"),
		call_stmt: node_kind("CallStmt"),
		branch: node_kind("If"),
		loop: node_kind("While"),
		ret: node_kind("Return"),
		bind: node_kind("Bind"),
		pattern: node_kind("PatName"),
		absent: node_kind("None"),
	)

// A call `receiver.method(arguments)`: the receiver node, the method name and the
// value node of each argument.
type Dotted:
	call: Int
	callee: Int
	receiver: Int
	method: String
	values: List[Int]
	named: Bool

fn dotted(s: Scan, at: Int) Dotted?:
	if s.tree.kind[at] != s.call: return none

	parts := children(s.tree, at)
	callee := parts[0]
	if s.tree.kind[callee] != s.member: return none

	var values = List[Int]()
	var named = false

	for argument in children(s.tree, parts[1]):
		values.append(children(s.tree, argument)[0])
		if s.tree.flags[argument] == 1: named = true

	return Dotted(
		call: at,
		callee: callee,
		receiver: children(s.tree, callee)[0],
		method: s.tree.names[s.tree.a[callee]].clone(),
		values: values,
		named: named,
	)

fn kind(s: Scan, at: Int) String:
	return kind_of(s.facts, s.tree.id[at])

fn report(s: Scan, code: String, severity: String, message: String, at: Int) Finding:
	return finding(
		code,
		severity,
		message,
		s.file,
		s.tree.offset[at],
		s.tree.line[at],
		s.tree.column[at],
	)

fn is_collection(text: String) Bool:
	return ["String", "List", "Map", "Set"].contains(text)

// `xs.length()` on a collection: the receiver node, or none.
fn length_of(s: Scan, at: Int) Int?:
	call_found := dotted(s, at)
	if call_found.is_none(): return none

	call := call_found.get()
	if call.method != "length" or not call.values.is_empty(): return none
	if not is_collection(kind(s, call.receiver)): return none

	return call.receiver

fn is_zero(s: Scan, at: Int) Bool:
	return s.tree.kind[at] == s.number and s.tree.names[s.tree.a[at]] == "0"

// `x.length() == 0`; in a condition also `!= 0` and `> 0` (MSL118).
fn emptiness(s: Scan, at: Int, condition: Bool, var out: List[Finding]) Void:
	if s.tree.kind[at] != s.binary: return

	op := s.tree.flags[at]
	parts := children(s.tree, at)

	if op == OP_AND or op == OP_OR:
		emptiness(s, parts[0], condition, out)
		emptiness(s, parts[1], condition, out)
		return

	if not is_zero(s, parts[1]): return

	receiver_found := length_of(s, parts[0])
	if receiver_found.is_none(): return

	receiver := receiver_found.get()
	text_found := span(
		s.source,
		first_offset(s.tree, receiver),
		last_offset(s.tree, receiver),
	)
	if text_found.is_none(): return

	text := text_found.get()
	var replacement = ""

	if op == OP_EQ and not condition: replacement = f"{text}.is_empty()"
	else if (op == OP_NE or op == OP_GT) and condition: replacement = f"not {text}.is_empty()"
	else: return

	found := report(
		s,
		"MSL118",
		"error",
		"Use is_empty() instead of comparing length() with 0",
		at,
	)
	out.append(
		with_fix(
			found,
			first_offset(s.tree, at),
			last_offset(s.tree, parts[1]),
			replacement,
		)
	)

// `xs.get(i)` on a list of copyable elements is `xs[i]` (MSL119).
fn list_get(s: Scan, at: Int, var out: List[Finding]) Void:
	call_found := dotted(s, at)
	if call_found.is_none(): return

	call := call_found.get()
	if call.method != "get" or call.values.length() != 1 or call.named: return
	if kind(s, call.receiver) != "List": return
	if not ["Int", "Float", "Bool"].contains(arg_of(s.facts, s.tree.id[call.receiver])): return

	receiver_kind := s.tree.kind[call.receiver]
	if receiver_kind != s.name and receiver_kind != s.member: return

	// The dot sits right after the receiver; a line break before it would leave
	// `xs\n[i]`.
	dot := s.tree.offset[call.callee] - 1
	if dot < 0 or s.source[dot] != 46 or last_offset(s.tree, call.receiver) != dot: return

	index_found := span(
		s.source,
		first_offset(s.tree, call.values[0]),
		last_offset(s.tree, call.values[0]),
	)
	if index_found.is_none(): return

	index := index_found.get()
	found := report(
		s,
		"MSL119",
		"error",
		"Index the list with xs[i] instead of xs.get(i)",
		at,
	)
	out.append(with_fix(found, dot, last_offset(s.tree, at), f"[{index}]"))

// `m.get(k).get_or(d)` on a map is `m.get_or(k, d)` (MSL120).
fn map_get_chain(s: Scan, at: Int, var out: List[Finding]) Void:
	outer_found := dotted(s, at)
	if outer_found.is_none(): return

	outer := outer_found.get()
	if outer.method != "get_or" or outer.values.length() != 1 or outer.named: return

	inner_found := dotted(s, outer.receiver)
	if inner_found.is_none(): return

	inner := inner_found.get()
	if inner.method != "get" or inner.values.length() != 1 or inner.named: return
	if kind(s, inner.receiver) != "Map": return

	dot := s.tree.offset[inner.callee] - 1
	end := last_offset(s.tree, at)
	if dot < 0 or s.source[dot] != 46: return

	key_found := span(
		s.source,
		first_offset(s.tree, inner.values[0]),
		last_offset(s.tree, inner.values[0]),
	)
	if key_found.is_none(): return

	key := key_found.get()
	fallback_found := span(
		s.source,
		first_offset(s.tree, outer.values[0]),
		last_offset(s.tree, outer.values[0]),
	)
	if fallback_found.is_none(): return

	fallback := fallback_found.get()

	// The edit replaces everything between the two calls, so a comment there would be
	// lost.
	between_found := span(s.source, dot, end)
	if between_found.is_none(): return

	between := between_found.get()
	if between.contains("//") or between.contains("/*"): return

	found := report(
		s,
		"MSL120",
		"error",
		"Use map.get_or(key, default) instead of map.get(key).get_or(default)",
		at,
	)
	out.append(with_fix(found, dot, end, f".get_or({key}, {fallback})"))

// A statement `r.get_or(none)` on a `Void!` is `void r` (MSL129); a statement `r.get()`
// on a Result faults on error (MSL130).
fn statement_get(s: Scan, at: Int, var out: List[Finding]) Void:
	call_found := dotted(s, at)
	if call_found.is_none(): return

	call := call_found.get()
	if call.method != "get" and call.method != "get_or": return
	if kind(s, call.receiver) != "Result": return

	if call.method == "get" and call.values.is_empty():
		out.append(
			report(
				s,
				"MSL130",
				"warning",
				"A statement `result.get()` faults when the call fails; write `call()?` in a function that returns a Result (`main` can return `Void!`), or `void call()` to ignore the outcome",
				at,
			)
		)
		return

	if call.method != "get_or" or call.values.length() != 1 or call.named: return
	if arg_of(s.facts, s.tree.id[call.receiver]) != "Void": return

	argument_found := span(
		s.source,
		first_offset(s.tree, call.values[0]),
		last_offset(s.tree, call.values[0]),
	)
	if argument_found.is_none(): return

	argument := argument_found.get()
	if argument != "none": return

	receiver_found := span(
		s.source,
		first_offset(s.tree, call.receiver),
		last_offset(s.tree, call.receiver),
	)
	if receiver_found.is_none(): return

	receiver := receiver_found.get()
	found := report(
		s,
		"MSL129",
		"error",
		"Use `void result` to ignore a Void! outcome instead of result.get_or(none)",
		at,
	)
	out.append(
		with_fix(
			found,
			first_offset(s.tree, call.receiver),
			last_offset(s.tree, at),
			f"void {receiver}",
		)
	)

// The only argument of a call to the plain name `name`, or -1.
fn sole_argument(s: Scan, at: Int, name: String) Int:
	if s.tree.kind[at] != s.call: return -1

	parts := children(s.tree, at)
	callee := parts[0]
	if s.tree.kind[callee] != s.name or s.tree.names[s.tree.a[callee]] != name: return (
		-1
	)

	arguments := children(s.tree, parts[1])
	if arguments.length() != 1: return -1

	return children(s.tree, arguments[0])[0]

// `print(call())` on a Result prints the wrapper (MSL131).
fn printed_result(s: Scan, at: Int, var out: List[Finding]) Void:
	value := sole_argument(s, at, "print")
	if value < 0 or kind(s, value) != "Result": return

	out.append(
		report(
			s,
			"MSL131",
			"warning",
			"`print` of a Result shows the `ok(...)` wrapper; write `call()?` in a function that returns a Result, or `if value := call():` to read the success",
			at,
		)
	)

// `xs.slice(a, b).get_or(fallback)` turns a range past the end into the fallback (MSL132).
fn slice_fallback(s: Scan, at: Int, var out: List[Finding]) Void:
	outer_found := dotted(s, at)
	if outer_found.is_none(): return

	outer := outer_found.get()
	if outer.method != "get_or" or kind(s, outer.receiver) != "Result": return

	inner_found := dotted(s, outer.receiver)
	if inner_found.is_none(): return

	inner := inner_found.get()
	if inner.method != "slice": return

	out.append(
		report(
			s,
			"MSL132",
			"warning",
			"`slice(..).get_or(..)` returns the fallback for any bad range, including an end past the length; use `?` to report it, or clamp the end with `min(end, xs.length())` first",
			at,
		)
	)

fn is_void_call(s: Scan, at: Int) Bool:
	return s.tree.kind[at] == s.call and kind(s, at) == "Void"

// `ys := xs.sort()` binds Void (MSL134).
fn bound_void(s: Scan, at: Int, var out: List[Finding]) Void:
	parts := children(s.tree, at)
	pattern := parts[0]
	if s.tree.kind[pattern] != s.pattern: return

	name := s.tree.names[s.tree.a[pattern]].clone()
	if name.starts_with("_") or not is_void_call(s, parts[2]): return

	out.append(
		report(
			s,
			"MSL134",
			"warning",
			f"`{name}` would hold Void: the call returns nothing, and sort() and reverse() change their receiver in place; call it as a statement, or use sorted() or reversed() for a new list",
			parts[2],
		)
	)

// `print(xs.sort())` prints `void` (MSL134).
fn printed_void(s: Scan, at: Int, var out: List[Finding]) Void:
	value := sole_argument(s, at, "print")
	if value < 0 or not is_void_call(s, value): return

	out.append(
		report(
			s,
			"MSL134",
			"warning",
			"this prints `void`: the call returns nothing, and sort() and reverse() change their receiver in place; call it as a statement, then print the list",
			value,
		)
	)

// `bytes.to_string()` renders `Bytes(104, 105)`, not the text (MSL135).
fn bytes_to_string(s: Scan, at: Int, var out: List[Finding]) Void:
	call_found := dotted(s, at)
	if call_found.is_none(): return

	call := call_found.get()
	if call.method != "to_string" or not call.values.is_empty(): return
	if kind(s, call.receiver) != "Bytes": return

	out.append(
		report(
			s,
			"MSL135",
			"warning",
			"`to_string()` on Bytes gives `Bytes(104, 105)`, not the text; `decode_utf8()` returns the text as a `String?`, so write `.decode_utf8().ok_or(Error(\"not UTF-8\", kind: \"EBADMSG\"))?`",
			at,
		)
	)

// A name or a field path over names: `k`, `it.sku`.
fn is_path(s: Scan, at: Int) Bool:
	if s.tree.kind[at] == s.name: return true
	if s.tree.kind[at] != s.member: return false

	return is_path(s, children(s.tree, at)[0])

// The source of the expression at `at` when it can stand alone in an edit; ""
// otherwise.
fn text_of(s: Scan, at: Int) String:
	found := span(s.source, first_offset(s.tree, at), last_offset(s.tree, at))
	if found.is_none(): return ""

	return found.get()

// `m[k.clone()] = m.get(k).get() op rest` on a map is `m[k] op= rest` (MSL127).
fn map_update(s: Scan, at: Int, var out: List[Finding]) Void:
	store_found := dotted(s, at)
	if store_found.is_none(): return

	store := store_found.get()
	if store.method != "[]=" or store.values.length() != 2 or store.named: return
	if not is_path(s, store.receiver) or kind(s, store.receiver) != "Map": return

	value := store.values[1]
	if s.tree.kind[value] != s.binary: return

	symbol := OPERATOR_UPDATES.get_or(s.tree.flags[value], "")
	if symbol.is_empty(): return

	parts := children(s.tree, value)
	unwrap_found := dotted(s, parts[0])
	if unwrap_found.is_none(): return

	unwrap := unwrap_found.get()
	if unwrap.method != "get" or not unwrap.values.is_empty(): return

	lookup_found := dotted(s, unwrap.receiver)
	if lookup_found.is_none(): return

	lookup := lookup_found.get()
	if lookup.method != "get" or lookup.values.length() != 1 or lookup.named: return
	if not is_path(s, lookup.values[0]) or not is_path(s, lookup.receiver): return

	map := text_of(s, store.receiver)
	again := text_of(s, lookup.receiver)
	key := text_of(s, lookup.values[0])
	index := text_of(s, store.values[0])
	rest := text_of(s, parts[1])
	if map.is_empty() or key.is_empty() or rest.is_empty(): return
	if map != again or (index != key and index != f"{key}.clone()"): return

	from := first_offset(s.tree, at)
	to := last_offset(s.tree, parts[1])
	whole := span(s.source, from, to)
	if whole.is_none() or whole.get().contains("//"): return

	found := report(
		s,
		"MSL127",
		"error",
		"Update the map entry in place with `m[k] op= value`",
		at,
	)
	out.append(with_fix(found, from, to, f"{map}[{key}] {symbol} {rest}"))

// A promise dropped as a statement is cancelled at once (MSL115); the fix waits for it.
fn dropped_promise(s: Scan, at: Int, var out: List[Finding]) Void:
	if kind(s, at) != "Promise": return

	from := first_offset(s.tree, at)
	to := last_offset(s.tree, at)
	found := report(
		s,
		"MSL115",
		"warning",
		"This promise is dropped as soon as it is made, which cancels it; bind it and call wait() on it, or pass it to wait_all",
		at,
	)
	text := span(s.source, from, to)

	if s.tree.kind[at] != s.call or text.is_none(): out.append(found)
	else: out.append(with_fix(found, from, to, f"void {text.get()} | .wait()"))

// Receiver kinds whose methods run to completion without waiting.
LOCAL_KINDS := [
	"Int", "Float", "Bool", "String", "List", "Map", "Set", "Optional", "Result",
	"Bytes"
]

// Whether the subtree at `at` can wait, call something that may, or leave the loop. A
// call counts as running to completion only when the checker typed its receiver as a
// primitive or a core collection; any other call, or an untyped one, may wait.
fn may_wait_or_exit(s: Scan, at: Int) Bool:
	node := s.tree.kind[at]
	if node == node_kind("Break") or node == s.ret: return true
	if node == node_kind("Lambda") or node == node_kind("Match"): return true

	if node == s.call:
		method := dotted(s, at)
		if method.is_none() or not LOCAL_KINDS.contains(kind(s, method.get().receiver)): return true

	for child in children(s.tree, at):
		if may_wait_or_exit(s, child): return true
	return false

fn imports_promise(s: Scan) Bool:
	for at in 0..s.tree.kind.length():
		if s.tree.kind[at] != node_kind("Import"): continue
		if s.tree.names[s.tree.b[at]].ends_with("promise.ms"): return true

	return false

// A `while true` loop whose body never waits starves its sibling tasks (MSL111).
fn busy_loop(s: Scan, at: Int, var out: List[Finding]) Void:
	parts := children(s.tree, at)
	cond := parts[0]
	if s.tree.kind[cond] != node_kind("Bool") or s.tree.flags[cond] != 1: return
	if may_wait_or_exit(s, parts[1]) or not imports_promise(s): return

	out.append(
		report(
			s,
			"MSL111",
			"error",
			"This loop never waits or exits, so other tasks cannot run and a timeout cannot stop it; wait inside the loop (sleep, or wait on a promise or a pipe), or return",
			cond,
		)
	)

// The findings of these rules for the module in `source`, given its checker facts.
export fn lint_typed_calls(
	tree: Syntax,
	facts: Facts,
	source: Bytes,
	file: String,
) List[Finding]:
	var out = List[Finding]()
	s := scan(tree.clone(), facts.clone(), source.clone(), file)

	for at in 0..tree.kind.length():
		parts := children(tree, at)
		node := tree.kind[at]

		if node == s.binary and tree.flags[at] == OP_EQ: emptiness(s, at, false, out)
		else if node == s.branch:
			if tree.kind[parts[0]] == s.absent: emptiness(s, parts[1], true, out)
		else if node == s.loop:
			emptiness(s, parts[0], true, out)
			busy_loop(s, at, out)
		else if node == s.ret and not parts.is_empty(): emptiness(
			s,
			parts[0],
			true,
			out,
		)
		else if node == s.call_stmt:
			statement_get(s, parts[0], out)
			printed_result(s, parts[0], out)
			map_update(s, parts[0], out)
			dropped_promise(s, parts[0], out)
		else if node == s.bind: bound_void(s, at, out)
		else if node == s.call:
			list_get(s, at, out)
			map_get_chain(s, at, out)
			slice_fallback(s, at, out)
			printed_void(s, at, out)
			bytes_to_string(s, at, out)

	return out

// A node the test says the checker typed.
type Typed:
	at: Int
	kind: String
	arg: String = ""

// The node indexes of the kind `kind_name` whose spelling is `spelling` (`""` for any).
fn nodes_of(tree: Syntax, kind_name: String, spelling: String) List[Int]:
	var found = List[Int]()

	for at in 0..tree.kind.length():
		if tree.kind[at] != node_kind(kind_name): continue

		if spelling.is_empty() or tree.names[tree.a[at]] == spelling: found.append(at)

	return found

fn facts_for(tree: Syntax, typed: List[Typed]) Facts:
	var rows = List[String]()

	for node in typed:
		arg := if node.arg.is_empty(): "" else: f", \"arg\": \"{node.arg}\""
		rows.append(f"\{\"id\": {tree.id[node.at]}, \"kind\": \"{node.kind}\"{arg}\}")

	return read_facts("{\"nodes\": [" + rows.join(", ") + "]}").get()

// The findings for `source` when the checker typed `typed`.
fn lint_with(source: String, typed: List[Typed]) List[Finding]:
	tree := parse(source).get()
	facts := facts_for(tree, typed)
	return lint_typed_calls(tree, facts, source.to_bytes(), "t.ms")

test "length compared with zero is emptiness, with the fix":
	source := "fn f(xs: List[Int]) Bool:\n    return xs.length() == 0\n"
	tree := parse(source).get()
	receiver := nodes_of(tree, "Name", "xs")[0]
	found := lint_with(source, [Typed(at: receiver, kind: "List")])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL118")?
	found[0].fix_text | expect_equal(expected: "xs.is_empty()")?
	lint_with(source, []).length() | expect_equal(expected: 0)?

test "a condition that compares length with zero reads not is_empty":
	source := "fn f(xs: List[Int]) Int:\n    if xs.length() > 0:\n        return 1\n    return 0\n"
	tree := parse(source).get()
	receiver := nodes_of(tree, "Name", "xs")[0]
	found := lint_with(source, [Typed(at: receiver, kind: "List")])
	found.length() | expect_equal(expected: 1)?
	found[0].fix_text | expect_equal(expected: "not xs.is_empty()")?

test "a map get chained with get_or is a get_or on the map":
	source := "fn f(m: Map[String, Int]) Int:\n    return m.get(\"a\").get_or(1)\n"
	tree := parse(source).get()
	receiver := nodes_of(tree, "Name", "m")[0]
	found := lint_with(source, [Typed(at: receiver, kind: "Map")])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL120")?
	found[0].fix_text | expect_equal(expected: ".get_or(\"a\", 1)")?

test "get on a list of copyable elements is an index":
	source := "fn f(xs: List[Int]) Int:\n    return xs.get(0).get_or(0)\n"
	tree := parse(source).get()
	receiver := nodes_of(tree, "Name", "xs")[0]
	found := lint_with(source, [Typed(at: receiver, kind: "List", arg: "Int")])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL119")?
	found[0].fix_text | expect_equal(expected: "[0]")?
	(
		lint_with(
			source,
			[Typed(at: receiver, kind: "List", arg: "String")],
		).length()
		| expect_equal(expected: 0)?
	)

test "a statement get on a Result faults, and get_or(none) on a Void! is void":
	source := "fn f(r: Int!, v: Void!) Void:\n    r.get()\n    v.get_or(none)\n"
	tree := parse(source).get()
	first := nodes_of(tree, "Name", "r")[0]
	second := nodes_of(tree, "Name", "v")[0]
	found := lint_with(
		source,
		[
			Typed(at: first, kind: "Result", arg: "Int"),
			Typed(at: second, kind: "Result", arg: "Void"),
		],
	)
	found.length() | expect_equal(expected: 2)?
	found[0].code | expect_equal(expected: "MSL130")?
	found[1].code | expect_equal(expected: "MSL129")?
	found[1].fix_text | expect_equal(expected: "void v")?

test "to_string on Bytes and a printed Void are reported":
	source := "fn f(b: Bytes, xs: List[Int]) Void:\n    print(b.to_string())\n    ys := xs.sort()\n"
	tree := parse(source).get()
	bytes_name := nodes_of(tree, "Name", "b")[0]
	calls := nodes_of(tree, "Call", "")
	sorted := calls[calls.length() - 1]
	found := lint_with(
		source,
		[Typed(at: bytes_name, kind: "Bytes"), Typed(at: sorted, kind: "Void")],
	)
	found.length() | expect_equal(expected: 2)?
	found[0].code | expect_equal(expected: "MSL135")?
	found[1].code | expect_equal(expected: "MSL134")?

test "a map entry rebuilt from its own lookup is updated in place":
	source := "fn f(m: Map[String, Int], k: String) Void:\n    m[k.clone()] = m.get(k).get() + 1\n"
	tree := parse(source).get()
	receiver := nodes_of(tree, "Name", "m")[0]
	found := lint_with(source, [Typed(at: receiver, kind: "Map")])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL127")?
	found[0].fix_text | expect_equal(expected: "m[k] += 1")?

test "a promise dropped as a statement is waited for":
	source := "fn f() Void:\n    promise(fn: work())\n"
	tree := parse(source).get()
	call := nodes_of(tree, "Call", "")[0]
	found := lint_with(source, [Typed(at: call, kind: "Promise")])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL115")?
	found[0].fix_text | expect_equal(expected: "void promise(fn: work()) | .wait()")?

test "a while true loop that never waits is reported when promises are in play":
	source := "import promise from \"@std/concurrency/promise.ms\"\n\nfn f() Void:\n    var i = 0\n    while true:\n        i += 1\n"
	found := lint_with(source, [])
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL111")?

	plain := "fn f() Void:\n    var i = 0\n    while true:\n        i += 1\n"
	lint_with(plain, []).length() | expect_equal(expected: 0)?

	waits := "import promise from \"@std/concurrency/promise.ms\"\n\nfn f() Void:\n    while true:\n        work()\n"
	lint_with(waits, []).length() | expect_equal(expected: 0)?
