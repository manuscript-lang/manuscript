// The occurrences of every declared name in one document: where each binding, module
// declaration, field, enum case and method is declared and used. The checker's facts
// (analysis.ms) say what a name resolves to, but only for expressions; the syntax tree
// supplies the names the checker leaves unrecorded (a called function, a written type,
// a declaration, a member) and the exact range of each. References, highlights and
// rename all read this one table.
//
// Identity is a key. A local binding is `b:<index>`; a module-level declaration is
// `s:<module>:<name>`; a field, case or method is `f:`, `c:` or `m:` and the key of its
// owner, a dot and its name. Two occurrences are the same entity exactly when their
// keys are equal, across documents too, because a module path names one file.
import (
	expect_equal, expect_ok from "@std/test/test.ms",

	Syntax, children, node_kind, parse from "../syntax.ms",
	BindingFact,
	Facts,
	NodeFact,
	RES_BINDING,
	RES_CASE,
	RES_FIELD,
	RES_SYMBOL,
	SymbolFact,
	analyze from "./analysis.ms",
)

export type Occurrence:
	key: String
	// The printed name.
	name: String
	// Byte range of the name in the document.
	start: Int
	end: Int
	declaration: Bool

// The module that stands for the document itself when the checker names none.
export LOCAL_MODULE := "main.ms"

fn name_of(tree: Syntax, at: Int) String:
	index := tree.a[at]
	if index < 0 or index >= tree.names.length(): return ""

	return tree.names[index].clone()

// The identifier a type text starts with: `List[Point]` and `Point?` are `List` and
// `Point`.
fn head_of(type_text: String) String:
	var end = 0

	for ch in type_text.chars():
		scalar := ch.scalar_at(0)
		word := (
			(scalar >= 48 and scalar <= 57)
			or (scalar >= 65 and scalar <= 90)
			or scalar == 95
			or (scalar >= 97 and scalar <= 122)
			or scalar > 127
		)
		if not word: break

		end += ch.length()

	return type_text.slice(0, end)

// Everything the walk needs, built once per document.
type Walk:
	facts: Facts
	tree: Syntax
	// The tree node index of each syntax node id, and the fact row of each id, -1 for
	// none.
	index_of_id: List[Int]
	fact_of_id: List[Int]
	// The row of `facts.methods` for each call node id, -1 for none.
	method_of_id: List[Int]
	parent: List[Int]
	// The module the document is, and the module-level declarations it writes.
	module: String
	declared: Map[String, Int]
	// The fact symbol of each name an import or an expression brought in.
	imported: Map[String, String]

fn symbol_key(module: String, name: String) String:
	return f"s:{module}:{name}"

fn key_of_type_name(walk: Walk, name: String) String:
	if walk.declared.get(name).is_some(): return symbol_key(walk.module, name)
	if found := walk.imported.get(name): return found.clone()

	return symbol_key("@std", name)

fn key_of_type_text(walk: Walk, type_text: String) String:
	return key_of_type_name(walk, head_of(type_text))

fn key_of_symbol(walk: Walk, symbol: SymbolFact) String:
	if symbol.local: return symbol_key(walk.module, symbol.name)
	return symbol_key(symbol.module, symbol.name)

fn put(
	var out: List[Occurrence],
	key: String,
	name: String,
	start: Int,
	declaration: Bool,
) Void:
	out.append(
		Occurrence(
			key: key,
			name: name.clone(),
			start: start,
			end: start + name.length(),
			declaration: declaration,
		)
	)

// The identity of binding `index`: a parameter of a declared function or method is the
// same parameter in every document that calls it by label, so it is keyed by its
// function; any other binding belongs to this document.
fn binding_key(walk: Walk, index: Int) String:
	fallback := f"b:{index}"
	binding := walk.facts.bindings[index]
	if (
		binding.role != 0
		or binding.node <= 0
		or binding.node >= walk.index_of_id.length()
	): return fallback

	param := walk.index_of_id[binding.node]
	if param < 0: return fallback

	list := walk.parent[param]
	if list < 0: return fallback

	owner := walk.parent[list]
	if owner < 0: return fallback

	kinds := kinds_of()
	callee := owner_key(walk, owner, kinds)
	if callee.is_empty(): return fallback

	return f"p:{callee}.{binding.name}"

// The key of the function or method that node `at` declares, "" for anything else.
fn owner_key(walk: Walk, at: Int, kinds: Kinds) String:
	tree := walk.tree
	kind := tree.kind[at]
	if kind == kinds.function and walk.parent[at] == 0: return symbol_key(
		walk.module,
		name_of(tree, at),
	)
	if kind == kinds.method: return method_key(walk.module, tree.offset[at])

	return ""

// A method is named by the module that declares it and where its name is written.
fn method_key(module: String, offset: Int) String:
	return f"m:{module}@{offset}"

fn symbol_by_id(walk: Walk, id: Int) SymbolFact?:
	for symbol in walk.facts.symbols:
		if symbol.id == id: return symbol.clone()
	return none

// The first spelling of `name` as a whole word at or after `from`: where a
// declaration writes its name after its keywords.
fn name_at_or_after(source: String, from: Int, name: String) Int:
	bytes := source.as_bytes()
	size := name.length()
	var at = from

	while at + size <= bytes.length():
		found := source.view(at, source.length()).index_of(name)
		if found.is_none(): return -1

		start := at + found.get()
		before := start > 0 and is_word_byte(bytes.get(start - 1))
		after := start + size < bytes.length() and is_word_byte(bytes.get(start + size))
		if not before and not after: return start

		at = start + 1

	return -1

fn is_word_byte(byte: UInt8) Bool:
	return (
		(byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or byte == 95
		or (byte >= 97 and byte <= 122)
		or byte > 127
	)

fn is_declaration_kind(kinds: List[Int], kind: Int) Bool:
	return kinds.contains(kind)

fn last_child_index(tree: Syntax, at: Int, want: Int) Int:
	var seen = 0
	var child = tree.first[at]

	while child >= 0:
		if seen == want: return child

		seen += 1
		child = tree.next[child]

	return -1

// The node at position `want` among the children of `at`, or -1.
fn child_at(tree: Syntax, at: Int, want: Int) Int:
	return last_child_index(tree, at, want)

fn fact_for(walk: Walk, at: Int) NodeFact?:
	id := walk.tree.id[at]
	if id <= 0 or id >= walk.fact_of_id.length(): return none

	row := walk.fact_of_id[id]
	if row < 0: return none

	return walk.facts.nodes[row].clone()

// The type text of the expression that node `at` is, or "".
fn type_of(walk: Walk, at: Int) String:
	node := fact_for(walk, at)
	if node.is_none(): return ""

	return node.get().type_text.clone()

// The key of the declaration the name node `at` resolved to, with the occurrence it
// is at, when the checker recorded one.
fn add_name(
	var out: List[Occurrence],
	walk: Walk,
	tree_at: Int,
	kinds: Kinds,
	source: String,
) Void:
	tree := walk.tree
	name := name_of(tree, tree_at)
	start := tree.offset[tree_at]
	node := fact_for(walk, tree_at)

	if known := node:
		if known.kind == RES_BINDING:
			put(out, binding_key(walk, known.target), name, start, false)
			return

		if known.kind == RES_SYMBOL:
			if symbol := symbol_by_id(walk, known.target):
				put(out, key_of_symbol(walk, symbol), name, start, false)
				return

		if known.kind == RES_CASE:
			owner := arm_owner(walk, tree_at, kinds)

			if not owner.is_empty():
				put(out, f"c:{owner}.{name}", name, start, false)
				return

	// The name of a called function or constructor: the checker keeps the symbol on
	// the call.
	parent := walk.parent[tree_at]

	if (
		parent >= 0
		and tree.kind[parent] == kinds.call
		and tree.first[parent] == tree_at
	):
		call := fact_for(walk, parent)

		if known := call:
			if known.callee >= 0:
				if symbol := symbol_by_id(walk, known.callee):
					put(out, key_of_symbol(walk, symbol), name, start, false)
					return

	// The path of a match arm.
	if parent >= 0 and tree.kind[parent] == kinds.arm and tree.first[parent] == tree_at:
		add_arm_path(out, walk, tree_at, kinds)
		return

	// A type named in an expression, as in `Shape.Dot`.
	if node.is_none() or node.get().kind == 0:
		if walk.declared.get(name).is_some() or walk.imported.get(name).is_some():
			put(out, key_of_type_name(walk, name), name, start, false)

// The key of the enum a match arm's path is a case of, "" when unknown.
fn arm_owner(walk: Walk, name_at: Int, kinds: Kinds) String:
	arm := walk.parent[name_at]
	if arm < 0 or walk.tree.kind[arm] != kinds.arm: return ""

	list := walk.parent[arm]
	if list < 0: return ""

	selection := walk.parent[list]
	if selection < 0 or walk.tree.kind[selection] != kinds.match_kind: return ""

	scrutinee := walk.tree.first[selection]
	if scrutinee < 0: return ""

	text := type_of(walk, scrutinee)
	if text.is_empty(): return ""

	return key_of_type_text(walk, text)

// The name of a called method: the checker records the call, not the member.
fn add_method_call(var out: List[Occurrence], walk: Walk, call: Int, kinds: Kinds) Void:
	tree := walk.tree
	id := tree.id[call]
	if id <= 0 or id >= walk.method_of_id.length() or walk.method_of_id[id] < 0: return

	callee := tree.first[call]
	if callee < 0 or tree.kind[callee] != kinds.member: return

	method := walk.facts.methods[walk.method_of_id[id]]
	if method.offset < 0: return

	name := name_of(tree, callee)
	put(out, method_key(method.module, method.offset), name, tree.offset[callee], false)

fn add_member(var out: List[Occurrence], walk: Walk, tree_at: Int) Void:
	tree := walk.tree
	node := fact_for(walk, tree_at)
	if node.is_none(): return

	known := node.get()
	left := tree.first[tree_at]
	if left < 0: return

	owner_text := type_of(walk, left)
	if owner_text.is_empty(): return

	owner := key_of_type_text(walk, owner_text)
	name := name_of(tree, tree_at)
	start := tree.offset[tree_at]

	if known.kind == RES_FIELD: put(out, f"f:{owner}.{name}", name, start, false)
	else if known.kind == RES_CASE: put(out, f"c:{owner}.{name}", name, start, false)

type Kinds:
	module: Int
	function: Int
	constant: Int
	type_decl: Int
	enum_decl: Int
	alias: Int
	interface: Int
	impl: Int
	method: Int
	param: Int
	type_param: Int
	type_named: Int
	name: Int
	member: Int
	call: Int
	arg: Int
	arm: Int
	match_kind: Int
	case: Int
	list: Int

fn kinds_of() Kinds:
	return Kinds(
		module: node_kind("Module"),
		function: node_kind("Fn"),
		constant: node_kind("Const"),
		type_decl: node_kind("Type"),
		enum_decl: node_kind("Enum"),
		alias: node_kind("Alias"),
		interface: node_kind("Interface"),
		impl: node_kind("Impl"),
		method: node_kind("Method"),
		param: node_kind("Param"),
		type_param: node_kind("TypeParam"),
		type_named: node_kind("TypeNamed"),
		name: node_kind("Name"),
		member: node_kind("Member"),
		call: node_kind("Call"),
		arg: node_kind("Arg"),
		arm: node_kind("Arm"),
		match_kind: node_kind("Match"),
		case: node_kind("Case"),
		list: node_kind("List"),
	)

// The type parameters a written type name can refer to: those of the declarations
// around it, innermost first.
fn type_parameter_of(
	walk: Walk,
	at: Int,
	name: String,
	owners: List[Int],
	params: List[Int],
) Int:
	var up = walk.parent[at]

	while up >= 0:
		for slot in 0..owners.length():
			if owners[slot] == up and name_of(walk.tree, params[slot]) == name:
				return params[slot]
		up = walk.parent[up]

	return -1

fn add_declaration(
	var out: List[Occurrence],
	walk: Walk,
	source: String,
	at: Int,
	name: String,
) Int:
	start := name_at_or_after(source, walk.tree.offset[at], name)
	if start >= 0: put(out, symbol_key(walk.module, name), name, start, true)
	return start

fn add_declared_members(
	var out: List[Occurrence],
	walk: Walk,
	source: String,
	at: Int,
	kinds: Kinds,
) Void:
	tree := walk.tree
	kind := tree.kind[at]
	name := name_of(tree, at)
	owner := symbol_key(walk.module, name)

	if kind == kinds.type_decl:
		fields := child_at(tree, at, 1)
		if fields < 0: return

		for field in children(tree, fields):
			if tree.kind[field] != kinds.param: continue

			field_name := name_of(tree, field)
			put(out, f"f:{owner}.{field_name}", field_name, tree.offset[field], true)

	if kind == kinds.enum_decl:
		cases := child_at(tree, at, 1)
		if cases < 0: return

		for item in children(tree, cases):
			if tree.kind[item] != kinds.case: continue

			case_name := name_of(tree, item)
			put(out, f"c:{owner}.{case_name}", case_name, tree.offset[item], true)

// The methods an `fn Type.name` or an interface declares, keyed by their owner.
fn add_methods(
	var out: List[Occurrence],
	walk: Walk,
	at: Int,
	owner: String,
	kinds: Kinds,
) Void:
	tree := walk.tree

	for list in children(tree, at):
		if tree.kind[list] != kinds.list: continue

		for item in children(tree, list):
			if tree.kind[item] != kinds.method: continue

			method_name := name_of(tree, item)
			put(
				out,
				method_key(walk.module, tree.offset[item]),
				method_name,
				tree.offset[item],
				true,
			)

// The label of a named argument names a field of the constructed type or a parameter
// of the called function.
fn add_label(var out: List[Occurrence], walk: Walk, at: Int, kinds: Kinds) Void:
	tree := walk.tree
	if tree.flags[at] % 2 == 0: return

	list := walk.parent[at]
	if list < 0: return

	call := walk.parent[list]
	if call < 0 or tree.kind[call] != kinds.call: return

	fact := fact_for(walk, call)
	if fact.is_none() or fact.get().callee < 0: return

	symbol := symbol_by_id(walk, fact.get().callee)
	if symbol.is_none(): return

	callee := key_of_symbol(walk, symbol.get())
	name := name_of(tree, at)
	start := tree.offset[at]

	if symbol.get().kind == 0:
		put(out, f"f:{callee}.{name}", name, start, false)
	else if symbol.get().kind == 1:
		put(out, f"p:{callee}.{name}", name, start, false)

// A match arm's path names a case of the scrutinee's enum.
fn add_arm_path(var out: List[Occurrence], walk: Walk, at: Int, kinds: Kinds) Void:
	tree := walk.tree
	owner := arm_owner(walk, at, kinds)
	if owner.is_empty(): return

	name := name_of(tree, at)
	put(out, f"c:{owner}.{name}", name, tree.offset[at], false)

// Every occurrence in the document, in source order.
export fn occurrences(
	source: String,
	facts: Facts,
	tree: Syntax,
	module: String,
) List[Occurrence]:
	kinds := kinds_of()
	total := tree.kind.length()
	var largest = 0
	for id in tree.id:
		if id > largest: largest = id

	var fact_of_id = [-1].repeated(largest + 1)

	for row in 0..facts.nodes.length():
		id := facts.nodes[row].id
		if id >= 0 and id <= largest: fact_of_id[id] = row

	var method_of_id = [-1].repeated(largest + 1)

	for row in 0..facts.methods.length():
		id := facts.methods[row].node
		if id >= 0 and id <= largest: method_of_id[id] = row

	var index_of_id = [-1].repeated(largest + 1)
	for at in 0..total:
		if tree.id[at] > 0: index_of_id[tree.id[at]] = at

	var parent = [-1].repeated(total)
	for at in 0..total:
		for child in children(tree, at):
			parent[child] = at

	var declared = Map[String, Int]()
	var own_module = module.clone()
	for symbol in facts.symbols:
		if symbol.local and own_module.is_empty(): own_module = symbol.module.clone()
	if own_module.is_empty(): own_module = LOCAL_MODULE

	var imported = Map[String, String]()
	for symbol in facts.symbols:
		if not symbol.local and not imported.contains(symbol.name):
			imported.add(symbol.name.clone(), symbol_key(symbol.module, symbol.name))

	for top in children(tree, 0):
		kind := tree.kind[top]
		named := (
			kind == kinds.function
			or kind == kinds.constant
			or kind == kinds.type_decl
			or kind == kinds.enum_decl
			or kind == kinds.alias
			or kind == kinds.interface
		)
		if named: declared.add(name_of(tree, top), top)

	walk := Walk(
		facts: facts.clone(),
		tree: tree.clone(),
		index_of_id: index_of_id,
		fact_of_id: fact_of_id,
		method_of_id: method_of_id,
		parent: parent,
		module: own_module,
		declared: declared,
		imported: imported,
	)
	var out: List[Occurrence] = []
	var owners: List[Int] = []
	var params: List[Int] = []

	for at in 0..total:
		if tree.kind[at] != kinds.type_param: continue

		list := walk.parent[at]
		if list < 0: continue

		owner := walk.parent[list]
		if owner < 0: continue

		owners.append(owner)
		params.append(at)

	for at in 0..total:
		kind := tree.kind[at]
		name := name_of(tree, at)

		if kind == kinds.name: add_name(out, walk, at, kinds, source)
		else if kind == kinds.member: add_member(out, walk, at)
		else if kind == kinds.arg: add_label(out, walk, at, kinds)
		else if kind == kinds.call: add_method_call(out, walk, at, kinds)
		else if kind == kinds.type_param:
			put(out, f"t:{at}", name, tree.offset[at], true)
		else if kind == kinds.type_named:
			param := type_parameter_of(walk, at, name, owners, params)

			if param >= 0: put(out, f"t:{param}", name, tree.offset[at], false)
			else if (
				walk.declared.get(name).is_some()
				or walk.imported.get(name).is_some()
			):
				put(out, key_of_type_name(walk, name), name, tree.offset[at], false)
		else if kind == kinds.impl:
			receiver := child_at(tree, at, 1)
			if receiver >= 0:
				add_methods(
					out,
					walk,
					at,
					key_of_type_name(walk, name_of(tree, receiver)),
					kinds,
				)
		else if kind == kinds.interface:
			add_declaration(out, walk, source, at, name)
			add_methods(out, walk, at, symbol_key(walk.module, name), kinds)
		else if (
			walk.parent[at] == 0
			and (
				kind == kinds.function
				or kind == kinds.constant
				or kind == kinds.type_decl
				or kind == kinds.enum_decl
				or kind == kinds.alias
			)
		):
			add_declaration(out, walk, source, at, name)
			add_declared_members(out, walk, source, at, kinds)

	for binding_at in 0..facts.bindings.length():
		binding := facts.bindings[binding_at]
		if binding.role == 1: continue
		if declared_at(out, binding.offset): continue

		put(out, binding_key(walk, binding_at), binding.name, binding.offset, true)

	out.sort(by_start)
	return out

fn declared_at(found: List[Occurrence], start: Int) Bool:
	for each in found:
		if each.declaration and each.start == start: return true
	return false

fn by_start(left: Occurrence, right: Occurrence) Int:
	if left.start != right.start: return if left.start < right.start: -1 else: 1
	return 0

fn index_source(source: String) List[Occurrence]:
	return occurrences(source, analyze(source).get(), parse(source).get(), "")

// The starts of the occurrences that share a key with the one written at `needle`
// (its first spelling in `source`), declaration first.
fn starts_with_same(source: String, found: List[Occurrence], needle: String) List[Int]:
	at := source.index_of(needle).get()
	var key = ""
	for each in found:
		if each.start == at: key = each.key.clone()

	var starts: List[Int] = []
	for each in found:
		if each.key == key: starts.append(each.start)
	return starts

test "a local is declared once and found at each use":
	source := "fn main() Int:\n\tcount := 1\n\treturn count + count\n"
	found := index_source(source)
	starts := starts_with_same(source, found, "count")
	expect_equal(starts.length(), 3)?
	expect_equal(starts[0], source.index_of("count").get())?

test "a function is found at its declaration, its calls and its labels":
	source := "fn add(left: Int, right: Int) Int:\n\treturn left + right\n\nfn main() Int:\n\treturn add(left: 1, right: 2)\n"
	found := index_source(source)
	expect_equal(starts_with_same(source, found, "add").length(), 2)?

	// The parameter is declared once, used in the body and named by one label.
	expect_equal(starts_with_same(source, found, "left").length(), 3)?
	expect_equal(starts_with_same(source, found, "right").length(), 3)?

test "a type, its fields and its cases are found through written types and members":
	source := "type Point:\n\tx: Int\n\ty: Int\n\nenum Shape:\n\tDot\n\tBox(w: Int)\n\nfn area(p: Point, s: Shape) Int:\n\tmatch s:\n\t\tDot: return p.x\n\t\tBox(w): return w\n\nfn main() Int:\n\tp := Point(x: 1, y: 2)\n\treturn area(p, Shape.Dot)\n"
	found := index_source(source)

	// Declaration, parameter type, constructor.
	expect_equal(starts_with_same(source, found, "Point").length(), 3)?

	// Declaration, parameter type, scrutinee uses and the qualified case.
	expect_equal(starts_with_same(source, found, "Shape").length(), 3)?

	// Declaration, member read and constructor label.
	expect_equal(starts_with_same(source, found, "x: Int").length(), 3)?

	// Declaration, match arm and qualified use.
	expect_equal(starts_with_same(source, found, "Dot").length(), 3)?

test "a method is found at its declaration and its calls":
	source := "type Dog:\n\tlabel: String\n\nfn Dog.name() String:\n\treturn self.label\n\nfn main() Int:\n\td := Dog(label: \"rex\")\n\tn := d.name()\n\treturn n.length()\n"
	found := index_source(source)
	expect_equal(starts_with_same(source, found, "name").length(), 2)?
	expect_equal(starts_with_same(source, found, "label").length(), 3)?

test "a type parameter is found where the declaration uses it":
	source := "fn first[T](items: List[T]) T?:\n\treturn items.first()\n"
	found := index_source(source)
	expect_equal(starts_with_same(source, found, "T").length() >= 3, true)?

test "two locals with one name are different entities":
	source := "fn main() Int:\n\ttotal := 1\n\tif total > 0:\n\t\ttotal2 := total + 1\n\t\treturn total2\n\treturn total\n"
	found := index_source(source)
	expect_equal(starts_with_same(source, found, "total").length(), 4)?
	expect_equal(starts_with_same(source, found, "total2").length(), 2)?
