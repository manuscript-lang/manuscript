// The lint rules about calls on a value whose type matters: `length()` compared with
// zero (MSL118), `get(i)` on a list (MSL119), a map `get` chained with `get_or`
// (MSL120), a Result `get` as a statement (MSL129, MSL130), a printed Result (MSL131),
// a `slice` with a fallback (MSL132), a Void value bound or printed (MSL134) and
// `to_string()` on Bytes (MSL135). Each reports only what the checker's facts prove, so
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
		else if node == s.loop: emptiness(s, parts[0], true, out)
		else if node == s.ret and not parts.is_empty(): emptiness(
			s,
			parts[0],
			true,
			out,
		)
		else if node == s.call_stmt:
			statement_get(s, parts[0], out)
			printed_result(s, parts[0], out)
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
