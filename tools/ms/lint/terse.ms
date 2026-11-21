// The terse-spelling rules that read only the syntax tree and the source text. A final
// `return` the end of the function already makes (MSL128) is the first.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Finding, finding, with_fix from "./finding.ms",
	balanced, first_offset, last_offset from "./spans.ms",
)

DROP_RETURN := "Drop the final return: the end of the function already returns it"

// The node kinds the rules look for.
type Kinds:
	absent: Int
	named: Int
	ret: Int
	nothing: Int
	call: Int
	name: Int
	func: Int
	impl: Int
	method: Int
	list: Int
	bind: Int
	pattern: Int
	loop: Int
	call_stmt: Int
	member: Int
	list_expr: Int
	number: Int
	assign: Int
	cond: Int

fn kinds() Kinds:
	return Kinds(
		absent: node_kind("None"),
		named: node_kind("TypeNamed"),
		ret: node_kind("Return"),
		nothing: node_kind("Void"),
		call: node_kind("Call"),
		name: node_kind("Name"),
		func: node_kind("Fn"),
		impl: node_kind("Impl"),
		method: node_kind("Method"),
		list: node_kind("List"),
		bind: node_kind("Bind"),
		pattern: node_kind("PatName"),
		loop: node_kind("For"),
		call_stmt: node_kind("CallStmt"),
		member: node_kind("Member"),
		list_expr: node_kind("ListExpr"),
		number: node_kind("Number"),
		assign: node_kind("Assign"),
		cond: node_kind("If"),
	)

fn name_of(tree: Syntax, at: Int) String:
	index := tree.a[at]
	if index < 0: return ""

	return tree.names[index].clone()

// Whether node `at` is the type `Void`.
fn is_void_type(tree: Syntax, k: Kinds, at: Int) Bool:
	return tree.kind[at] == k.named and name_of(tree, at) == "Void"

// `ok()` or `ok(void)`.
fn is_ok_unit(tree: Syntax, k: Kinds, at: Int) Bool:
	if tree.kind[at] != k.call: return false

	parts := children(tree, at)
	callee := parts[0]
	if tree.kind[callee] != k.name or name_of(tree, callee) != "ok": return false

	args := children(tree, parts[1])
	if args.is_empty(): return true
	if args.length() != 1: return false

	arg := args[0]
	if tree.flags[arg] % 2 == 1: return false

	return tree.kind[children(tree, arg)[0]] == k.nothing

fn is_space(byte: UInt8) Bool: byte == 32

// The final `return` of `result` and `body` when it only repeats what falling off the
// end does. `source` is the text the tree was parsed from.
fn trailing_return(
	tree: Syntax,
	k: Kinds,
	source: Bytes,
	file: String,
	result: Int,
	body: Int,
	var out: List[Finding],
) Void:
	if tree.kind[result] != k.named: return

	args := children(tree, children(tree, result)[0])
	unit_result := (
		name_of(tree, result) == "Result"
		and args.length() == 2
		and is_void_type(tree, k, args[0])
	)
	statements := children(tree, body)
	if statements.length() < 2: return
	if not (unit_result or is_void_type(tree, k, result)): return

	last := statements[statements.length() - 1]
	if tree.kind[last] != k.ret: return

	value := children(tree, last)[0]
	absent := tree.kind[value] == k.absent
	redundant := if absent or tree.kind[value] == k.nothing: not unit_result else: unit_result and is_ok_unit(
		tree,
		k,
		value,
	)
	if not redundant: return

	end := if absent: tree.offset[last] + 6 else: tree.end_offset[value]
	var from = tree.offset[last]
	while from > 0 and is_space(source[from - 1]): from -= 1

	var to = end

	if to + 1 < source.length() and source[to] == 13 and source[to + 1] == 10: to += 2
	else if to < source.length() and source[to] == 10: to += 1

	if from == 0 or source[from - 1] != 10: return
	if source.view(from, to).contains("//".to_bytes()): return

	found := finding(
		"MSL128",
		"error",
		DROP_RETURN,
		file,
		tree.offset[last],
		tree.line[last],
		tree.column[last],
	)
	out.append(with_fix(found, from, to, ""))

// `name := value` straight before `return name` in the statements `first` and `second` is
// `return value` (MSL126).
fn temp_return(
	tree: Syntax,
	k: Kinds,
	source: Bytes,
	file: String,
	first: Int,
	second: Int,
	var out: List[Finding],
) Void:
	if tree.kind[first] != k.bind or tree.kind[second] != k.ret: return
	if tree.flags[first] / 2 % 2 == 1: return

	parts := children(tree, first)
	if tree.kind[parts[0]] != k.pattern or tree.kind[parts[1]] != k.absent: return

	value := children(tree, second)[0]
	if tree.kind[value] != k.name or name_of(tree, value) != name_of(tree, parts[0]): return

	written := source.view(first_offset(tree, parts[2]), tree.end_offset[parts[2]])
	if written.contains("\n".to_bytes()) or not balanced(written): return
	if source.view(tree.offset[first], tree.end_offset[value]).contains("//".to_bytes()): return

	found := finding(
		"MSL126",
		"error",
		"Return the value directly instead of binding it first",
		file,
		tree.offset[first],
		tree.line[first],
		tree.column[first],
	)
	value_text := written.decode_utf8().get_or("")
	out.append(
		with_fix(
			found,
			tree.offset[first],
			tree.end_offset[value],
			f"return {value_text}",
		)
	)

// The arguments of statement `at` when it is a call of the method `method`, or none.
fn method_call(tree: Syntax, k: Kinds, at: Int, method: String) List[Int]:
	if tree.kind[at] != k.call_stmt: return []

	call := children(tree, at)[0]
	if tree.kind[call] != k.call: return []

	parts := children(tree, call)
	if tree.kind[parts[0]] != k.member or name_of(tree, parts[0]) != method: return []

	return children(tree, parts[1])

// Whether statement `at` is `<receiver>.append(<one argument>)` on the name `receiver`.
fn appends_to(tree: Syntax, k: Kinds, at: Int, receiver: String) Bool:
	args := method_call(tree, k, at, "append")
	if args.length() != 1: return false

	callee := children(tree, children(tree, at)[0])[0]
	left := children(tree, callee)[0]
	return tree.kind[left] == k.name and name_of(tree, left) == receiver

// `var out = []` followed by a loop that only appends to it, or `var total = 0` followed
// by a loop that only adds into it (MSL124).
fn accumulate_loop(
	tree: Syntax,
	k: Kinds,
	source: Bytes,
	file: String,
	first: Int,
	second: Int,
	var out: List[Finding],
) Void:
	if tree.kind[first] != k.bind or tree.flags[first] % 2 == 0: return
	if tree.kind[second] != k.loop: return

	parts := children(tree, first)
	if tree.kind[parts[0]] != k.pattern: return

	name := name_of(tree, parts[0])
	body := children(tree, children(tree, second)[1])
	if body.length() != 1: return

	only := body[0]
	value := parts[2]
	var hit = ""

	if is_empty_list(tree, k, source, value):
		guarded := guarded_append(tree, k, only, name)
		if appends_to(tree, k, only, name) or guarded:
			hit = "Build the list with `xs.map(fn x: ...)` or `xs.filter(fn x: ...)` instead of a loop that appends"
	else if tree.kind[value] == k.number and tree.kind[only] == k.assign:
		if (
			tree.flags[only] / 2 % 2 == 1
			and tree.flags[only] % 2 == 0
			and name_of(tree, only) == name
			and tree.flags[only] / 256 == 8
		):
			hit = "Total with `xs.sum()` or `xs.map(...).sum()` instead of a loop that adds"

	if hit.is_empty(): return

	out.append(
		finding(
			"MSL124",
			"warning",
			hit,
			file,
			tree.offset[first],
			tree.line[first],
			tree.column[first],
		)
	)

// `[]` or `List[T]()`.
fn is_empty_list(tree: Syntax, k: Kinds, source: Bytes, value: Int) Bool:
	if tree.kind[value] == k.list_expr: return children(tree, value).is_empty()

	written := source.view(first_offset(tree, value), tree.end_offset[value])
	return (
		written.starts_with("List[".to_bytes())
		and written.ends_with("]()".to_bytes())
		and not written.contains("\n".to_bytes())
	)

// Whether `only` is `if cond: name.append(...)` with no binding and no else.
fn guarded_append(tree: Syntax, k: Kinds, only: Int, name: String) Bool:
	if tree.kind[only] != k.cond: return false

	parts := children(tree, only)
	if tree.kind[parts[0]] != k.absent: return false
	if not children(tree, parts[3]).is_empty(): return false

	body := children(tree, parts[2])
	return body.length() == 1 and appends_to(tree, k, body[0], name)

// How many times the name `name` is read in the subtree at `at`.
fn count_reads(tree: Syntax, k: Kinds, at: Int, name: String) Int:
	var total = if tree.kind[at] == k.name and name_of(tree, at) == name: 1 else: 0
	for child in children(tree, at): total += count_reads(tree, k, child, name)
	return total

// How many times `needle` appears in `text`.
fn occurrences(text: Bytes, needle: Bytes) Int:
	var total = 0
	var from = 0

	while from + needle.length() <= text.length():
		if text.view(from, from + needle.length()) == needle:
			total += 1
			from += needle.length()
		else:
			from += 1

	return total

// `for i in 0..xs.length():` that only reads `xs[i]` is `for x in xs:` (MSL123).
fn index_loop(
	tree: Syntax,
	k: Kinds,
	source: Bytes,
	file: String,
	at: Int,
	var out: List[Finding],
) Void:
	if tree.kind[at] != k.loop: return

	parts := children(tree, at)
	iter := parts[0]
	written := source.view(first_offset(tree, iter), tree.end_offset[iter])
	if written.contains("\n".to_bytes()) or not balanced(written): return

	text := written.decode_utf8().get_or("")
	if not text.starts_with("0..") or not text.ends_with(".length()"): return

	list := text.slice(3, text.length() - 9)
	if list.is_empty(): return

	letters := list.to_bytes()

	for position in 0..letters.length():
		c := letters[position]
		alnum := (
			(c >= 48 and c <= 57)
			or (c >= 65 and c <= 90)
			or (c >= 97 and c <= 122)
			or c == 95
			or c >= 128
		)
		if not alnum: return

	name := name_of(tree, at)
	total := count_reads(tree, k, parts[1], name)
	var end = last_offset(tree, parts[1])

	// An index expression ends before its closing bracket.
	while end < source.length() and source[end] == 93: end += 1

	indexed := occurrences(
		source.view(tree.offset[at], end),
		f"{list}[{name}]".to_bytes(),
	)
	if total == 0 or total != indexed: return

	out.append(
		finding(
			"MSL123",
			"warning",
			f"Loop over the list directly: `for item in {list}:` instead of indexing {list}[{name}]",
			file,
			tree.offset[at],
			tree.line[at],
			tree.column[at],
		)
	)

// `for x in xs: out.append(x)` is `out.extend(xs)` (MSL125).
fn append_all(
	tree: Syntax,
	k: Kinds,
	file: String,
	at: Int,
	var out: List[Finding],
) Void:
	if tree.kind[at] != k.loop: return

	body := children(tree, children(tree, at)[1])
	if body.length() != 1 or method_call(tree, k, body[0], "append").length() != 1: return

	arg := children(tree, children(tree, children(tree, body[0])[0])[1])[0]
	value := children(tree, arg)[0]
	var element = (
		tree.kind[value] == k.name
		and name_of(tree, value) == name_of(tree, at)
	)

	if tree.kind[value] == k.call:
		parts := children(tree, value)
		callee := parts[0]

		if children(tree, parts[1]).is_empty() and tree.kind[callee] == k.member:
			left := children(tree, callee)[0]
			element = (
				name_of(tree, callee) == "clone"
				and tree.kind[left] == k.name
				and name_of(tree, left) == name_of(tree, at)
			)

	if not element: return

	out.append(
		finding(
			"MSL125",
			"warning",
			"Append every element with `out.extend(xs)` instead of a loop",
			file,
			tree.offset[at],
			tree.line[at],
			tree.column[at],
		)
	)

// The findings of the terse rules for the module in `text`; none when it does not
// parse.
export fn lint_terse(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	tree := parsed.get()
	k := kinds()
	source := text.to_bytes()

	for at in 0..tree.kind.length():
		if tree.kind[at] != k.list: continue

		statements := children(tree, at)

		for i in 1..statements.length():
			temp_return(tree, k, source, file, statements[i - 1], statements[i], out)
			accumulate_loop(
				tree,
				k,
				source,
				file,
				statements[i - 1],
				statements[i],
				out,
			)

	for at in 0..tree.kind.length():
		append_all(tree, k, file, at, out)
		index_loop(tree, k, source, file, at, out)

	for decl in children(tree, 0):
		if tree.kind[decl] == k.func:
			parts := children(tree, decl)
			trailing_return(tree, k, source, file, parts[2], parts[3], out)
		else if tree.kind[decl] == k.impl:
			for method in children(tree, children(tree, decl)[3]):
				parts := children(tree, method)
				count := parts.length()
				trailing_return(
					tree,
					k,
					source,
					file,
					parts[count - 2],
					parts[count - 1],
					out,
				)

	return out

test "a final bare return of a Void function is dropped":
	source := "fn f(x: Int) Void:\n    print(x)\n    return\n\nfn g(x: Int) Int:\n    return x\n"
	found := lint_terse("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL128")?
	found[0].line | expect_equal(expected: 3)?
	found[0].fix_from | expect_equal(expected: 32)?
	found[0].fix_to | expect_equal(expected: 43)?

test "a value bound and returned at once is returned directly":
	source := "fn f(x: Int) Int:\n    y := x + 1\n    return y\n\nfn g(x: Int) Int:\n    y := x + 1\n    return x\n"
	found := lint_terse("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL126")?
	found[0].line | expect_equal(expected: 2)?

test "a loop that only appends or adds is a library call":
	source := "fn f(xs: List[Int]) Int:\n    var a = List[Int]()\n    for x in xs: a.append(x + 1)\n    var t = 0\n    for x in xs: t += x\n    var b = []\n    for x in xs: b.append(x)\n    return t\n"
	found := lint_terse("t.ms", source)
	var codes: List[String] = []
	for item in found: codes.append(item.code.clone())
	codes | expect_equal(expected: ["MSL124", "MSL124", "MSL124", "MSL125"])?

test "a loop that only indexes the list is a loop over the list":
	source := "fn f(xs: List[Int]) Int:\n    var t = 0\n    for i in 0..xs.length():\n        t += xs[i]\n        print(t)\n    for j in 0..xs.length():\n        t += xs[j] + j\n        print(t)\n    return t\n"
	found := lint_terse("t.ms", source)
	found.length() | expect_equal(expected: 1)?
	found[0].code | expect_equal(expected: "MSL123")?
	found[0].line | expect_equal(expected: 3)?
