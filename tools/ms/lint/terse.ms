// The terse-spelling rules that read only the syntax tree and the source text. A final
// `return` the end of the function already makes (MSL128) is the first.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	Finding, finding from "./finding.ms",
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

	out.append(
		finding(
			"MSL128",
			"warning",
			DROP_RETURN,
			file,
			tree.offset[last],
			tree.line[last],
			tree.column[last],
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
