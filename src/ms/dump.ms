// The canonical syntax-tree text of crates/ms-syntax/src/dump.rs, printed from the
// Manuscript reader (`syntax.ms`). `src/compiler/tools/ms_syntax_dump ast` prints the
// same text from the C tree, so equal output over the corpus shows the table carries
// everything the dump reads.
import Syntax, children, node_kind, parse from "./syntax.ms"

fn unary_text(op: Int) String:
	if op == 0: return "not"
	if op == 1: return "-"
	if op == 2: return "+"

	return "try"

fn binary_text(op: Int) String: [
	"or", "and", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%"
][op]

fn hex2(value: Int) String:
	digits := "0123456789abcdef"
	return digits.slice(value / 16, value / 16 + 1).concat(
		digits.slice(value % 16, value % 16 + 1)
	)

fn quote(text: String) String:
	var out = "\""
	bytes := text.as_bytes()

	for i in 0..bytes.length():
		byte := bytes[i].to_int()

		if byte >= 32 and byte < 127 and byte != 34 and byte != 92: out = out.concat(
			text.slice(i, i + 1)
		)
		else: out = out.concat(f"\\x{hex2(byte)}")

	return out.concat("\"")

fn pos_text(line: Int, column: Int, offset: Int) String: f"{line}:{column}:{offset}"

fn node_pos(t: Syntax, i: Int) String: pos_text(t.line[i], t.column[i], t.offset[i])

fn name_text(t: Syntax, sym: Int) String:
	if sym < 0: return quote("")
	return quote(t.names[sym])

// Kind indexes, looked up once.
type Kinds:
	none: Int
	list: Int
	pos: Int
	module: Int
	fn_decl: Int
	const_decl: Int
	type_decl: Int
	enum_decl: Int
	alias_decl: Int
	interface_decl: Int
	impl_decl: Int
	test_decl: Int
	type_named: Int
	number: Int
	bool_expr: Int
	void_expr: Int
	text: Int
	name: Int
	member: Int
	apply: Int
	index: Int
	probe: Int
	list_expr: Int
	map: Int
	unary: Int
	binary: Int
	lambda: Int
	call: Int
	match_expr: Int
	pat_name: Int
	pat_list: Int
	bind: Int
	assign: Int
	call_stmt: Int
	return_stmt: Int
	break_stmt: Int
	continue_stmt: Int
	if_stmt: Int
	while_stmt: Int
	for_stmt: Int

fn kinds() Kinds:
	return Kinds(
		none: node_kind("None"),
		list: node_kind("List"),
		pos: node_kind("Pos"),
		module: node_kind("Module"),
		fn_decl: node_kind("Fn"),
		const_decl: node_kind("Const"),
		type_decl: node_kind("Type"),
		enum_decl: node_kind("Enum"),
		alias_decl: node_kind("Alias"),
		interface_decl: node_kind("Interface"),
		impl_decl: node_kind("Impl"),
		test_decl: node_kind("Test"),
		type_named: node_kind("TypeNamed"),
		number: node_kind("Number"),
		bool_expr: node_kind("Bool"),
		void_expr: node_kind("Void"),
		text: node_kind("Text"),
		name: node_kind("Name"),
		member: node_kind("Member"),
		apply: node_kind("Apply"),
		index: node_kind("Index"),
		probe: node_kind("Probe"),
		list_expr: node_kind("ListExpr"),
		map: node_kind("Map"),
		unary: node_kind("Unary"),
		binary: node_kind("Binary"),
		lambda: node_kind("Lambda"),
		call: node_kind("Call"),
		match_expr: node_kind("Match"),
		pat_name: node_kind("PatName"),
		pat_list: node_kind("PatList"),
		bind: node_kind("Bind"),
		assign: node_kind("Assign"),
		call_stmt: node_kind("CallStmt"),
		return_stmt: node_kind("Return"),
		break_stmt: node_kind("Break"),
		continue_stmt: node_kind("Continue"),
		if_stmt: node_kind("If"),
		while_stmt: node_kind("While"),
		for_stmt: node_kind("For"),
	)

fn typ(t: Syntax, k: Kinds, at: Int) String:
	if t.kind[at] == k.none: return "nil"

	parts := children(t, at)
	if t.kind[at] == k.type_named:
		return f"(type {node_pos(t, at)} {name_text(t, t.a[at])} {types(t, k, parts[0])} {params(t, k, -1)} nil)"

	return f"(type {node_pos(t, at)} {quote("fn")} [] {params(t, k, parts[0])} {typ(t, k, parts[1])})"

fn types(t: Syntax, k: Kinds, list: Int) String:
	var out = "["
	for at in children(t, list): out = out.concat(f"{typ(t, k, at)} ")
	return out.concat("]")

// `list` is the Params list node, or -1 for none.
fn params(t: Syntax, k: Kinds, list: Int) String:
	var out = "["

	if list >= 0:
		for at in children(t, list):
			parts := children(t, at)
			out = out.concat(
				f"(param {node_pos(t, at)} {name_text(t, t.a[at])} {typ(t, k, parts[0])} {expr(t, k, parts[1])}) "
			)

	return out.concat("]")

fn body(t: Syntax, k: Kinds, list: Int) String:
	var out = "["
	for at in children(t, list): out = out.concat(f"{stmt(t, k, at)} ")
	return out.concat("]")

fn pattern(t: Syntax, k: Kinds, at: Int) String:
	if t.kind[at] == k.none: return "nil"
	if t.kind[at] == k.pat_name: return f"(pattern {node_pos(t, at)} name {name_text(t, t.a[at])} [] [])"

	if t.kind[at] == k.pat_list:
		var out = f"(pattern {node_pos(t, at)} list {quote("")} ["
		for item in children(t, at): out = out.concat(f"{pattern(t, k, item)} ")
		return out.concat("] [])")

	var out = f"(pattern {node_pos(t, at)} type {quote("")} [] ["

	for field in children(t, at):
		inner := children(t, field)
		out = out.concat(
			f"(pf {node_pos(t, field)} {name_text(t, t.a[field])} {pattern(t, k, inner[0])}) "
		)

	return out.concat("])")

type Fields:
	kind: String
	text: String = "\"\""
	left: String = "nil"
	right: String = "nil"
	args: String = ""
	types: String = "[]"
	elements: String = ""
	parts: String = ""
	params: String = "[]"
	result: String = "nil"
	body: String = "[]"
	arms: String = ""

fn expr(t: Syntax, k: Kinds, at: Int) String:
	if t.kind[at] == k.none: return "nil"

	kind := t.kind[at]
	kids := children(t, at)
	var f = Fields(kind: "match")

	if kind == k.number: f = Fields(kind: "number", text: quote(t.names[t.a[at]]))
	else if kind == k.bool_expr: f = Fields(
		kind: "bool",
		text: if t.flags[at] == 1: quote("true") else: quote("false"),
	)
	else if kind == k.void_expr: f = Fields(kind: "void", text: quote("void"))
	else if kind == k.name: f = Fields(kind: "name", text: quote(t.names[t.a[at]]))
	else if kind == k.text:
		var parts = ""

		for part in kids:
			if t.flags[part] == 1: parts = parts.concat(
				f"(part {quote("")} {expr(t, k, children(t, part)[0])}) "
			)
			else: parts = parts.concat(f"(part {quote(t.names[t.a[part]])} nil) ")

		f = Fields(kind: "text", text: quote(""), parts: parts)
	else if kind == k.member: f = Fields(
		kind: "member",
		text: quote(t.names[t.a[at]]),
		left: expr(t, k, kids[0]),
	)
	else if kind == k.apply: f = Fields(
		kind: "apply",
		text: quote(""),
		left: expr(t, k, kids[0]),
		right: expr(t, k, kids[2]),
		types: types(t, k, kids[1]),
	)
	else if kind == k.index: f = Fields(
		kind: "index",
		text: quote(""),
		left: expr(t, k, kids[0]),
		right: expr(t, k, kids[1]),
	)
	else if kind == k.probe: f = Fields(
		kind: "probe",
		text: quote(""),
		left: expr(t, k, kids[0]),
	)
	else if kind == k.list_expr:
		var elements = ""
		for item in kids: elements = elements.concat(f"{expr(t, k, item)} ")
		f = Fields(kind: "list", text: quote("["), elements: elements)
	else if kind == k.map:
		var elements = ""

		for entry in kids:
			pair := children(t, entry)
			elements = elements.concat(f"{expr(t, k, pair[0])} {expr(t, k, pair[1])} ")

		f = Fields(kind: "map", text: quote("{"), elements: elements)
	else if kind == k.unary: f = Fields(
		kind: "unary",
		text: quote(unary_text(t.flags[at])),
		right: expr(t, k, kids[0]),
	)
	else if kind == k.binary: f = Fields(
		kind: "binary",
		text: quote(binary_text(t.flags[at])),
		left: expr(t, k, kids[0]),
		right: expr(t, k, kids[1]),
	)
	else if kind == k.lambda: f = Fields(
		kind: "lambda",
		text: quote(""),
		params: params(t, k, kids[0]),
		result: typ(t, k, kids[1]),
		body: body(t, k, kids[2]),
	)
	else if kind == k.call:
		var args = ""

		for arg in children(t, kids[1]):
			value := children(t, arg)[0]
			name := if t.flags[arg] == 1: name_text(t, t.a[arg]) else: quote("")
			args = args.concat(f"(arg {node_pos(t, arg)} {name} {expr(t, k, value)}) ")

		f = Fields(kind: "call", text: quote(""), left: expr(t, k, kids[0]), args: args)
	else:
		var arms = ""

		for arm in children(t, kids[1]):
			parts := children(t, arm)
			var bindings = ""
			for binding in children(t, parts[1]): bindings = bindings.concat(
				f"({name_text(t, t.a[binding])} {node_pos(t, binding)}) "
			)
			arms = arms.concat(
				f"(arm {node_pos(t, arm)} {expr(t, k, parts[0])} [{bindings}] {body(t, k, parts[2])} {expr(t, k, parts[3])}) "
			)

		f = Fields(
			kind: "match",
			text: quote("match"),
			left: expr(t, k, kids[0]),
			arms: arms,
		)

	return f"(expr {node_pos(t, at)} {f.kind} {f.text} {f.left} {f.right} [{f.args}] {f.types} [{f.elements}] [{f.parts}] {f.params} {f.result} {f.body} [{f.arms}])"

fn stmt(t: Syntax, k: Kinds, at: Int) String:
	kind := t.kind[at]
	kids := children(t, at)
	var name = quote("")
	var compound = quote("")
	var mutable = "false"
	var group = "0:0:0"
	var pat = "nil"
	var ty = "nil"
	var target = "nil"
	var value = "nil"
	var main_body = "[]"
	var else_body = "[]"
	var label = ""

	if kind == k.bind:
		label = "bind"
		if t.flags[at] % 2 == 1: mutable = "true"
		if t.flags[at] / 2 % 2 == 1: group = pos_text(
			t.end_line[at],
			t.end_column[at],
			t.end_offset[at],
		)
		pat = pattern(t, k, kids[0])
		ty = typ(t, k, kids[1])
		value = expr(t, k, kids[2])
	else if kind == k.assign:
		label = "assign"
		if t.flags[at] / 2 % 2 == 1: compound = quote(binary_text(t.flags[at] / 256))

		if t.flags[at] % 2 == 1: target = expr(t, k, kids[0])
		else: name = quote(t.names[t.a[at]])

		value = expr(t, k, kids[1])
	else if kind == k.call_stmt:
		label = "call"
		value = expr(t, k, kids[0])
	else if kind == k.return_stmt:
		label = "return"
		value = expr(t, k, kids[0])
	else if kind == k.break_stmt: label = "break"
	else if kind == k.continue_stmt: label = "continue"
	else if kind == k.if_stmt:
		label = "if"
		if t.flags[at] == 1: mutable = "true"
		pat = pattern(t, k, kids[0])
		value = expr(t, k, kids[1])
		main_body = body(t, k, kids[2])
		else_body = body(t, k, kids[3])
	else if kind == k.while_stmt:
		label = "while"
		value = expr(t, k, kids[0])
		main_body = body(t, k, kids[1])
	else:
		label = "for"
		name = quote(t.names[t.a[at]])
		value = expr(t, k, kids[0])
		main_body = body(t, k, kids[1])

	return f"(stmt {node_pos(t, at)} {label} {name} {compound} {mutable} {group} {pat} {ty} {target} {value} {main_body} {else_body})"

fn type_params(t: Syntax, k: Kinds, list: Int) String:
	var out = "["

	for at in children(t, list):
		parts := children(t, at)
		out = out.concat(
			f"(tp {node_pos(t, at)} {name_text(t, t.a[at])} {types(t, k, parts[0])} {typ(t, k, parts[1])}) "
		)

	return out.concat("]")

// One `(decl ...)`. Absent parts are the empty list or nil, as the Rust declaration
// prints them.
type Decl:
	pos: String
	kind: String
	name: String
	exported: Bool = false
	constant: Bool = false
	synthetic: Bool = false
	tparams: String = "[]"
	fields: String = "[]"
	cases: String = ""
	methods: String = ""
	params: String = "[]"
	result: String = "nil"
	contract: String = "nil"
	receiver: String = "nil"
	body: String = "[]"

fn decl_text(f: Decl) String:
	exported := if f.exported: "true" else: "false"
	constant := if f.constant: "true" else: "false"
	synthetic := if f.synthetic: "true" else: "false"
	return f"(decl {f.pos} {f.kind} {f.name} {exported} {constant} 0:0:0 {synthetic} {f.tparams} {f.fields} [{f.cases}] [{f.methods}] {f.params} {f.result} {f.contract} {f.receiver} {f.body})"

fn methods_text(t: Syntax, k: Kinds, list: Int) String:
	var out = ""

	for method in children(t, list):
		// A method's children: the `var` position, receiver arguments, type parameters,
		// parameters, result, body.
		parts := children(t, method)
		out = out.concat(
			decl_text(
				Decl(
					pos: node_pos(t, method),
					kind: "fn",
					name: name_text(t, t.a[method]),
					tparams: type_params(t, k, parts[2]),
					params: params(t, k, parts[3]),
					result: typ(t, k, parts[4]),
					body: body(t, k, parts[5]),
				)
			)
		)
		out = out.concat(" ")

	return out

fn decl(t: Syntax, k: Kinds, at: Int) String:
	kind := t.kind[at]
	kids := children(t, at)
	exported := t.flags[at] % 2 == 1
	synthetic := t.flags[at] / 2 % 2 == 1
	external := t.flags[at] / 4 % 2 == 1
	base := Decl(
		pos: node_pos(t, at),
		kind: "",
		name: "",
		exported: exported,
		synthetic: synthetic,
	)
	if kind == k.fn_decl:
		return decl_text(
			Decl(
				pos: base.pos,
				kind: if external: "extern fn" else: "fn",
				name: name_text(t, t.a[at]),
				exported: exported,
				synthetic: synthetic,
				tparams: type_params(t, k, kids[0]),
				params: params(t, k, kids[1]),
				result: typ(t, k, kids[2]),
				body: body(t, k, kids[3]),
			)
		)

	if kind == k.const_decl:
		// The dump prints a constant as a function returning the value; a missing type
		// is an unnamed one.
		value := kids[1]
		placeholder := f"(type {node_pos(t, value)} {quote("")} [] [] nil)"
		result := if t.kind[kids[0]] == k.none: placeholder else: typ(t, k, kids[0])
		init := kids[2]
		stmt_text := f"(stmt {node_pos(t, init)} return {quote("")} {quote("")} false 0:0:0 nil nil nil {expr(t, k, value)} [] [])"
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "fn",
				name: name_text(t, t.a[at]),
				exported: exported,
				constant: true,
				synthetic: synthetic,
				result: result,
				body: f"[{stmt_text} ]",
			)
		)

	if kind == k.type_decl:
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "type",
				name: name_text(t, t.a[at]),
				exported: exported,
				synthetic: synthetic,
				tparams: type_params(t, k, kids[0]),
				fields: params(t, k, kids[1]),
			)
		)

	if kind == k.enum_decl:
		var cases = ""
		for case in children(t, kids[1]):
			cases = cases.concat(
				f"(case {node_pos(t, case)} {name_text(t, t.a[case])} {params(t, k, children(t, case)[0])}) "
			)
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "alternative",
				name: name_text(t, t.a[at]),
				exported: exported,
				synthetic: synthetic,
				tparams: type_params(t, k, kids[0]),
				cases: cases,
			)
		)

	if kind == k.alias_decl:
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "alias",
				name: name_text(t, t.a[at]),
				exported: exported,
				synthetic: synthetic,
				tparams: type_params(t, k, kids[0]),
			)
		)
	if kind == k.interface_decl:
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "interface",
				name: name_text(t, t.a[at]),
				exported: exported,
				synthetic: synthetic,
				tparams: type_params(t, k, kids[0]),
				methods: methods_text(t, k, kids[1]),
			)
		)
	if kind == k.impl_decl:
		return decl_text(
			Decl(
				pos: base.pos,
				kind: "impl",
				name: quote(""),
				exported: exported,
				synthetic: synthetic,
				methods: methods_text(t, k, kids[3]),
				contract: typ(t, k, kids[0]),
				receiver: typ(t, k, kids[1]),
			)
		)

	// A test or bench: a function returning Void.
	unit := f"(type {node_pos(t, at)} {quote("Void")} [] [] nil)"
	return decl_text(
		Decl(
			pos: base.pos,
			kind: if t.flags[at] / 16 % 2 == 1: "bench" else: "test",
			name: name_text(t, t.a[at]),
			exported: exported,
			synthetic: synthetic,
			result: unit,
			body: body(t, k, kids[0]),
		)
	)

// The dump of one parsed module, as `ms_syntax_dump ast` prints it for one file.
export fn dump_module(tree: Syntax) String:
	k := kinds()
	var out = ""
	imports := tree.a[0]
	all := children(tree, 0)

	for i in 0..all.length():
		at := all[i]

		if i < imports:
			parts := children(tree, at)
			out = out.concat(
				f"import {node_pos(tree, at)} {node_pos(tree, parts[1])} {name_text(tree, tree.a[at])} {quote(tree.names[tree.b[at]])}\n"
			)
		else: out = out.concat(f"{decl(tree, k, at)}\n")

	return out.concat(f"omitted []\nrecovered []\nnodes {tree.b[0]}\n")

// Dumps `text`, or the first syntax error as the dump prints it.
export fn dump_text(text: String) String:
	match parse(text):
		ok(tree): return dump_module(tree)
		error(failure): return f"error {failure.line}:{failure.column}:{failure.offset}\n"
