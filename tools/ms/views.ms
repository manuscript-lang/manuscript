// The `ms diagram` views over the fact model: the tree views (calls, effects, errors,
// modules, flow, scope, tasks, types, ownership, overview) and their ASCII, Mermaid and
// JSON renderings. Port of crates/ms-tooling/src/views.rs and tree.rs; the Rust code is
// the oracle (`ms-tooling-dev view FILE VIEW ENTITY DEPTH ascii|mermaid|json`).
//
// Until the C checker builds the facts, they are read from the JSON file
// `ms-tooling-dev facts FILE` prints.
//   ms run tools/ms/views.ms -- FACTS.json VIEW [ENTITY] [DEPTH] [ascii|mermaid|json]
import (
	Arg, Command, FlagKind, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",
	is_alphabetic, is_numeric from "@std/unicode.ms",

	run_tool from "./cli.ms",
	json_string from "./docgen.ms",
)

// Bounds one view so a large project stays readable and the output size predictable.
export NODE_CAP := 200
export VIEWS := [
	"overview", "calls", "effects", "errors", "modules", "flow", "scope", "tasks",
	"types", "ownership"
]

// ---- The fact model, as `ms-tooling-dev facts` prints it ----

export type Slot:
	name: String
	ty: String
	exclusive: Bool
	mode: String
	refs: List[String]

export type Fact:
	key: String
	file: String
	kind: String
	name: String
	line: Int
	effects: List[String]
	error: String
	tries: Int
	scopes: Int
	calls: List[String]
	external: List[String]
	slots: List[Slot]
	result_ownership: String
	result_borrow: Bool
	receiver: String
	result: Slot?
	// Read by tools/ms/review.ms; older fact files lack them.
	label: String = ""
	ty: String = ""
	exported: Bool = false
	reach: List[String] = []
	permits: List[String] = []
	first: Int = 0
	last: Int = 0
	// False when the C checker could not see everything the entity calls: effects,
	// reach, permits and calls are then empty, not zero.
	effects_known: Bool = true
	// False when the C checker did not keep the function in its ownership walk: scopes,
	// result_ownership and the slot modes are then empty, not zero.
	ownership_known: Bool = true

// One line of a view: a label and what hangs under it.
export type Node:
	label: String
	kind: String = ""
	reference: String = ""
	file: String = ""
	line: Int = 0
	omitted: Int = 0
	children: List[Node] = []

export type Import:
	file: String
	paths: List[String]

export type Flow:
	key: String
	steps: List[Node]

export type Facts:
	entities: List[Fact]
	imports: List[Import]
	flows: List[Flow]

// The facts with the lookups the views share. `entities` is in key order.
export type Model:
	facts: Facts
	index: Map[String, Int]
	flow_index: Map[String, Int]

export fn model_of(facts: Facts) Model:
	var index = Map[String, Int]()
	for i in 0..facts.entities.length(): index.add(facts.entities[i].key.clone(), i)

	var flow_index = Map[String, Int]()
	for i in 0..facts.flows.length(): flow_index.add(facts.flows[i].key.clone(), i)
	return Model(facts: facts, index: index, flow_index: flow_index)

fn plain(label: String) Node: Node(label: label)

fn has(items: List[String], text: String) Bool: items.contains(text)

fn plural_s(n: Int) String: if n == 1: "" else: "s"

// ---- Text helpers ----

fn effect_list(effects: List[String]) String:
	if effects.is_empty(): return "none"
	return effects.join("+")

fn or_none(text: String) String: if text.is_empty(): "none" else: text.clone()

// `@std/time.ms#fn#monotonic` reads `@std/time.ms::monotonic`; text that is not a
// `file#kind#name` ID is returned unchanged.
fn readable_id(id: String) String:
	parts := id.split("#")
	if parts.length() < 3: return id.clone()

	file := parts[0]
	kind := parts[1]
	name := parts.drop(2).join("#")
	if file.is_empty() or kind.is_empty() or name.is_empty(): return id.clone()

	return f"{file.cut_suffix("+source").get_or(file)}::{name}"

fn is_word(ch: String) Bool: (
	is_alphabetic(ch.scalar_at(0))
	or is_numeric(ch.scalar_at(0))
)

// Every character that is not a letter or digit becomes `_` (and `keep_underscore`
// keeps one).
fn sanitize(text: String, keep_underscore: Bool) String:
	var out = ""

	for ch in text.chars():
		if is_word(ch) or (keep_underscore and ch == "_"): out = out.concat(ch)
		else: out = out.concat("_")

	return out

fn head_label(f: Fact) String: f"{f.name}  [{f.kind}] {f.file}:{f.line}"

fn head_node(f: Fact) Node:
	return Node(
		label: head_label(f),
		reference: f.key.clone(),
		kind: f.kind.clone(),
		file: f.file.clone(),
		line: f.line,
	)

fn capped_note(skipped: Int) Node: plain(
	f"+{skipped} more (output capped at {NODE_CAP} nodes)"
)

fn var Node.cap(skipped: Int) Void:
	if skipped > 0:
		self.omitted = skipped
		self.children.append(capped_note(skipped))

// ---- Lookup ----

fn empty_fact() Fact:
	return Fact(
		key: "",
		file: "",
		kind: "",
		name: "",
		line: 0,
		effects: [],
		error: "",
		tries: 0,
		scopes: 0,
		calls: [],
		external: [],
		slots: [],
		result: none,
		result_ownership: "",
		result_borrow: false,
		receiver: "",
	)

// The entity with `key`, or one with an empty key.
fn Model.get(key: String) Fact: self.fact(key).get_or(empty_fact())

fn Model.fact(key: String) Fact?:
	if i := self.index.get(key): return self.facts.entities[i].clone()
	return none

fn is_callable(f: Fact) Bool: f.kind == "fn" or f.kind == "method" or f.kind == "test"

fn is_data_type(f: Fact) Bool: (
	f.kind == "type"
	or f.kind == "alternative"
	or f.kind == "interface"
)

// Resolves a name, `file::name`, or full key to exactly one entity. An exact key takes
// precedence over display names and qualified names.
fn Model.find_entity(name: String) Fact!:
	if exact := self.fact(name): return ok(exact)

	var matches = List[Fact]()
	for f in self.facts.entities:
		if f.name == name or f"{f.file}::{f.name}" == name: matches.append(f.clone())
	if matches.length() == 1: return ok(matches[0].clone())
	if matches.is_empty(): return error(
		Error(
			f"no entity named {name}; use a declaration name, file::name, or full entity ID file#kind#name (ms review lists the public surface)"
		)
	)

	var keys = matches.map(fn f: f"{f.file}::{f.name}")

	// A type and its impl share file::name; a test display name can equal another
	// entity's qualified name or full key. Count all name matches before offering
	// qualified-name remedies.
	var counts = Map[String, Int]()
	for key in keys: counts.add(key.clone(), 0)

	for f in self.facts.entities:
		if n := counts.get(f.name): counts.add(f.name.clone(), n + 1)

		qualified := f"{f.file}::{f.name}"
		if qualified != f.name:
			if n := counts.get(qualified): counts.add(qualified.clone(), n + 1)

	var usable = true

	for i in 0..keys.length():
		if exact := self.fact(keys[i]):
			if exact.key != matches[i].key: usable = false
		else if counts.get_or(keys[i], 0) != 1: usable = false

	if not usable: keys = matches.map(fn f: f.key.clone())
	return error(Error(f"{name} is ambiguous; use one of: {keys.join(", ")}"))

// ---- Generic views: calls, effects, errors ----

// Drops callees that cannot answer the view's question.
fn relevant(view: String, f: Fact) Bool:
	if view == "effects": return not f.effects.is_empty()
	if view == "errors": return not f.error.is_empty() or f.tries > 0

	return true

type ViewBuilder:
	view: String
	depth: Int
	count: Int = 0
	skipped: Int = 0

fn ViewBuilder.label(f: Fact) String:
	if self.view == "effects": return f"{f.name}  effects: {effect_list(f.effects)}"
	if self.view == "errors": return f"{f.name}  error: {or_none(f.error)}, try sites: {f.tries}"

	return head_label(f)

fn var ViewBuilder.expand(model: Model, f: Fact, level: Int, var path: Set[String]) Node:
	var node = Node(
		label: self.label(f),
		reference: f.key.clone(),
		kind: f.kind.clone(),
		file: f.file.clone(),
		line: f.line,
	)
	self.count += 1
	if level >= self.depth: return node

	path.add(f.key.clone())

	for key in f.calls:
		callee := model.get(key)
		if callee.key.is_empty(): continue
		if not relevant(self.view, callee): continue

		if path.contains(key):
			if self.count >= NODE_CAP:
				self.skipped += 1
				continue

			self.count += 1
			node.children.append(
				Node(
					label: f"{callee.name}  (cycle)",
					kind: "cycle",
					reference: callee.key.clone(),
					file: callee.file.clone(),
					line: callee.line,
				)
			)
			continue

		if self.count >= NODE_CAP:
			self.skipped += 1
			continue

		node.children.append(self.expand(model, callee, level + 1, path))

	if self.view == "effects" or self.view == "calls":
		for target in f.external:
			if self.view == "effects" and f.effects.is_empty(): break

			if self.count >= NODE_CAP:
				self.skipped += 1
				continue

			self.count += 1
			node.children.append(
				Node(
					label: readable_id(target),
					kind: "external",
					reference: target.clone(),
				)
			)

	path.remove(f.key.clone())
	return node

fn Model.mark_reachable(view: String, start: String, var seen: Set[String]) Void:
	var pending = [start.clone()]

	while not pending.is_empty():
		key := pending.pop().get_or("")
		if seen.contains(key): continue

		seen.add(key.clone())

		fact := self.get(key)
		if fact.key.is_empty(): continue

		for callee in fact.calls:
			if target := self.fact(callee):
				if relevant(view, target): pending.append(callee.clone())

fn Model.view_roots(view: String, entity: String) List[Fact]!:
	if not entity.is_empty(): return ok([self.find_entity(entity)?])

	var called = Set[String]()

	for f in self.facts.entities:
		if not relevant(view, f): continue

		for key in f.calls:
			if callee := self.fact(key):
				if relevant(view, callee): called.add(key.clone())

	// `entities` is in key order already.
	var roots = List[Fact]()
	for f in self.facts.entities:
		if is_callable(f) and relevant(view, f) and not called.contains(f.key): roots.append(
			f.clone()
		)

	// Every callable must be reachable from a root, including disconnected recursive
	// groups, which have no node with zero incoming edges.
	var reached = Set[String]()
	for root in roots: self.mark_reachable(view, root.key, reached)

	for f in self.facts.entities:
		if is_callable(f) and relevant(view, f) and not reached.contains(f.key):
			roots.append(f.clone())
			self.mark_reachable(view, f.key, reached)

	return ok(roots)

// ---- Modules ----

fn Model.modules_view(entity: String) Node!:
	var files = List[Import]()
	for imp in self.facts.imports:
		if entity.is_empty() or imp.file == entity: files.append(imp.clone())
	if not entity.is_empty() and files.is_empty(): return error(
		Error(
			f"no module named {entity}; use a project-relative path such as src/main.ms"
		)
	)

	var root = plain("MODULES VIEW")
	var count = 0
	var skipped = 0

	for imp in files:
		if count >= NODE_CAP:
			skipped += 1
			continue

		count += 1

		var module = Node(
			label: imp.file.clone(),
			kind: "module",
			file: imp.file.clone(),
		)

		for path in imp.paths:
			if count >= NODE_CAP:
				skipped += 1
				continue

			count += 1
			module.children.append(plain(path.clone()))

		root.children.append(module)

	if files.is_empty(): root.children.append(plain("none"))
	root.cap(skipped)
	return ok(root)

// ---- Flow, scope and tasks ----

type FlowExpander:
	depth: Int
	count: Int = 0
	skipped: Int = 0

fn Model.steps(key: String) List[Node]:
	if i := self.flow_index.get(key): return self.facts.flows[i].steps.clone()
	return []

fn var FlowExpander.expand(
	model: Model,
	nodes: List[Node],
	level: Int,
	var path: Set[String],
) List[Node]:
	var out = List[Node]()

	for n in nodes:
		if self.count >= NODE_CAP:
			self.skipped += 1
			continue

		self.count += 1

		var copied = Node(
			label: n.label.clone(),
			kind: n.kind.clone(),
			reference: n.reference.clone(),
			file: n.file.clone(),
			line: n.line,
		)
		copied.children = self.expand(model, n.children, level, path)

		if not n.reference.is_empty() and level < self.depth:
			if path.contains(n.reference): copied.children.append(plain("(cycle)"))
			else:
				path.add(n.reference.clone())
				copied.children.extend(
					self.expand(
						model,
						model.steps(n.reference),
						level + 1,
						path,
					)
				)
				path.remove(n.reference.clone())

		out.append(copied)

	return out

// Keeps cleanup scopes and, inside them, the exits that run the cleanup: return, break,
// continue, and try sites.
fn prune_scopes(nodes: List[Node], in_scope: Bool) List[Node]:
	var out = List[Node]()

	for n in nodes:
		kids := prune_scopes(n.children, in_scope or n.kind == "scope")
		exit := in_scope and (n.kind == "exit" or n.kind == "try")
		if n.kind == "scope" or exit or not kids.is_empty():
			out.append(
				Node(
					label: n.label.clone(),
					kind: n.kind.clone(),
					file: n.file.clone(),
					line: n.line,
					children: kids,
				)
			)

	return out

// Keeps task groups (resource scopes holding a spawn) and the work each spawn starts.
fn prune_tasks(nodes: List[Node]) List[Node]:
	var out = List[Node]()

	for n in nodes:
		if n.kind == "spawn":
			out.append(n.clone())
			continue

		kids := prune_tasks(n.children)
		if not kids.is_empty():
			out.append(
				Node(
					label: n.label.clone(),
					kind: n.kind.clone(),
					file: n.file.clone(),
					line: n.line,
					children: kids,
				)
			)

	return out

fn Model.flow_view(view: String, entity: String, depth: Int) Node!:
	if entity.is_empty(): return error(
		Error(
			f"{view} needs --entity; name a function or method (ms review lists the public surface)"
		)
	)

	f := self.find_entity(entity)?
	var expander = FlowExpander(depth: depth)
	var root = plain(f"{view.upper()} VIEW")
	var path = Set[String]()
	path.add(f.key.clone())

	var body = expander.expand(self, self.steps(f.key), 1, path)
	if view == "scope": body = prune_scopes(body, false)
	if view == "tasks": body = prune_tasks(body)

	var header = head_node(f)
	header.children = body
	if header.children.is_empty(): header.children = [plain("none")]
	root.children.append(header)
	root.cap(expander.skipped)
	return ok(root)

// ---- Ownership ----

fn ownership_candidates(model: Model) List[Fact]:
	var out = List[Fact]()
	for f in model.facts.entities:
		if (
			(f.kind == "fn" or f.kind == "method")
			and (f.scopes > 0 or f.slots.any(fn s: s.exclusive))
		): out.append(f.clone())
	return out

fn slot_mode(s: Slot) String: if s.exclusive: "var" else: s.mode.clone()

type OwnershipBuilder:
	depth: Int
	count: Int = 0

fn var OwnershipBuilder.node(
	model: Model,
	f: Fact,
	level: Int,
	var path: Set[String],
) Node:
	var node = head_node(f)
	self.count += 1

	if f.kind == "interface":
		// An operation fixes only how it takes `self`; its other modes are the
		// implementer's.
		for op in f.slots:
			mode := if op.exclusive: "var (exclusive borrow)" else: "borrow"
			node.children.append(plain(f"{op.name}{op.ty}  self {mode}"))

		return node

	for s in f.slots:
		mode := if s.exclusive: "var (exclusive borrow)" else: s.mode.clone()

		if mode.is_empty(): node.children.append(plain(f"{s.name}: {s.ty}"))
		else: node.children.append(plain(f"{s.name}: {s.ty}  {mode}"))

	if r := f.result: node.children.append(
		plain(f"returns {r.ty}  {f.result_ownership}")
	)

	// After the parameters and result: pages index those positionally.
	if f.receiver == "var": node.children.append(plain("self  var (exclusive borrow)"))
	else if not f.receiver.is_empty(): node.children.append(
		plain(f"self  {f.receiver}")
	)

	if f.scopes > 0: node.children.append(plain(f"closes {f.scopes} resource scope(s)"))
	if level >= self.depth: return node

	path.add(f.key.clone())

	for key in f.calls:
		callee := model.get(key)
		if callee.key.is_empty(): continue
		if path.contains(key) or self.count >= NODE_CAP: continue

		node.children.append(self.node(model, callee, level + 1, path))

	path.remove(f.key.clone())
	return node

fn Model.ownership_view(entity: String, depth: Int) Node!:
	var roots = List[Fact]()

	if entity.is_empty(): roots = ownership_candidates(self)
	else: roots.append(self.find_entity(entity)?)

	var root = plain("OWNERSHIP VIEW")
	var builder = OwnershipBuilder(depth: depth)
	var skipped = 0

	for f in roots:
		if builder.count >= NODE_CAP:
			skipped += 1
			continue

		var path = Set[String]()
		root.children.append(builder.node(self, f, 0, path))

	if roots.is_empty(): root.children.append(plain("none"))
	root.cap(skipped)
	return ok(root)

// ---- Types ----

type TypeBuilder:
	depth: Int
	count: Int = 0

fn slot_label(f: Fact, s: Slot) String:
	if s.name.is_empty(): return f"returns {s.ty}"
	if f.kind == "alternative" and (s.ty.starts_with("(") or s.ty.is_empty()): return f"case {s.name}{s.ty}"

	return f"{s.name}: {s.ty}"

fn var TypeBuilder.node(model: Model, f: Fact, level: Int, var path: Set[String]) Node:
	var node = head_node(f)
	self.count += 1
	if level >= self.depth: return node

	path.add(f.key.clone())

	var slots = f.slots.clone()
	if r := f.result: slots.append(r.clone())

	for s in slots:
		if self.count >= NODE_CAP: break

		self.count += 1

		var child = plain(slot_label(f, s))

		for key in s.refs:
			target := model.get(key)
			if target.key.is_empty(): continue

			if path.contains(key):
				child.children.append(
					Node(
						label: f"{target.name}  (cycle)",
						kind: "cycle",
						reference: key.clone(),
					)
				)
			else if self.count < NODE_CAP: child.children.append(
				self.node(model, target, level + 1, path)
			)

		node.children.append(child)

	path.remove(f.key.clone())
	return node

fn Model.type_roots() List[Fact]:
	var held = Set[String]()
	for f in self.facts.entities:
		if f.kind == "type" or f.kind == "alternative":
			for s in f.slots:
				for key in s.refs: held.add(key.clone())

	var all = List[Fact]()
	var tops = List[Fact]()

	for f in self.facts.entities:
		if is_data_type(f):
			all.append(f.clone())
			if not held.contains(f.key): tops.append(f.clone())

	if tops.is_empty(): return all

	return tops

fn Model.types_view(entity: String, depth: Int) Node!:
	var roots = List[Fact]()

	if entity.is_empty(): roots = self.type_roots()
	else: roots.append(self.find_entity(entity)?)

	var root = plain("TYPES VIEW")
	var builder = TypeBuilder(depth: depth)
	var skipped = 0

	for f in roots:
		if builder.count >= NODE_CAP:
			skipped += 1
			continue

		var path = Set[String]()
		root.children.append(builder.node(self, f, 0, path))

	if roots.is_empty(): root.children.append(plain("none"))
	root.cap(skipped)
	return ok(root)

// ---- Overview ----

type ModuleSummary:
	file: String
	fns: Int = 0
	types: Int = 0
	tests: Int = 0
	entry: Bool = false
	effects: List[String] = []
	calls: List[CallEdge] = []

type CallEdge:
	file: String
	count: Int

// The system level: each project module, what it holds, the effects it reaches, and
// which modules it calls. Module order is by file name.
fn Model.overview() List[ModuleSummary]:
	var files = self.facts.imports.map(fn i: i.file.clone())
	files.sort()

	var summaries = Map[String, ModuleSummary]()
	for file in files: summaries.add(file.clone(), ModuleSummary(file: file.clone()))

	for f in self.facts.entities:
		if not summaries.contains(f.file): continue

		var m = summaries.get_or(f.file, ModuleSummary(file: ""))

		if f.kind == "fn" or f.kind == "method":
			m.fns += 1
			if f.name == "main": m.entry = true
		else if is_data_type(f): m.types += 1
		else if f.kind == "test" or f.kind == "bench": m.tests += 1

		for e in f.effects:
			if not m.effects.contains(e): m.effects.append(e.clone())

		for key in f.calls:
			target := self.get(key)
			if target.key.is_empty(): continue
			if target.file == f.file: continue

			var found = false

			for i in 0..m.calls.length():
				if m.calls[i].file == target.file:
					m.calls[i].count += 1
					found = true

			if not found: m.calls.append(CallEdge(file: target.file.clone(), count: 1))

		summaries.add(f.file.clone(), m)

	var out = List[ModuleSummary]()

	for file in files:
		var m = summaries.get_or(file, ModuleSummary(file: ""))
		m.effects.sort()
		m.calls.sort(fn a, b: a.file.compare(b.file))
		out.append(m)

	return out

fn module_summary(m: ModuleSummary) String:
	var parts = [f"{m.fns} fn"]
	if m.tests > 0: parts.append(f"{m.tests} test{plural_s(m.tests)}")
	if m.types > 0: parts.append(f"{m.types} type{plural_s(m.types)}")
	return parts.join(", ")

fn call_count(n: Int) String: f"{n} call{plural_s(n)}"

fn module_head(m: ModuleSummary) String:
	entry := if m.entry: "  [entry]" else: ""
	return f"{m.file}{entry}  {module_summary(m)}  effects: {effect_list(m.effects)}"

fn overview_tree(modules: List[ModuleSummary]) Node:
	var root = plain("OVERVIEW VIEW")

	for m in modules.take(NODE_CAP):
		var node = Node(label: module_head(m), kind: "module", file: m.file.clone())
		for edge in m.calls: node.children.append(
			plain(f"-> {edge.file}  ({call_count(edge.count)})")
		)
		root.children.append(node)

	if modules.is_empty(): root.children.append(plain("none"))
	return root

fn overview_ascii(modules: List[ModuleSummary]) String:
	var out = ""

	for m in modules.take(NODE_CAP):
		out = out.concat(f"{module_head(m)}\n")
		for edge in m.calls: out = out.concat(
			f"  -> {edge.file}  ({call_count(edge.count)})\n"
		)

	if modules.is_empty(): out = out.concat("none\n")
	return out

fn overview_mermaid(modules: List[ModuleSummary]) String:
	var out = "flowchart LR\n"

	for m in modules.take(NODE_CAP):
		class := if m.entry: "entry" else if m.effects.is_empty(): "pure" else: "effect"
		out = out.concat(
			f"    m_{sanitize(m.file, false)}[\"{m.file}<br/>{module_summary(m)}<br/>{effect_list(m.effects)}\"]:::{class}\n"
		)

	for m in modules.take(NODE_CAP):
		for edge in m.calls:
			out = out.concat(
				f"    m_{sanitize(m.file, false)} -->|{call_count(edge.count)}| m_{sanitize(edge.file, false)}\n"
			)
	out = out.concat("    classDef entry fill:#d6e9ff,stroke:#37b,stroke-width:3px\n")
	out = out.concat("    classDef pure fill:#dff5e1,stroke:#2a2\n")
	out = out.concat("    classDef effect fill:#fff3cd,stroke:#b8860b\n")
	return out

// ---- Building a view ----

export fn build_view(model: Model, view: String, entity: String, depth_in: Int) Node!:
	var depth = depth_in
	if depth <= 0:
		depth = if view == "flow" or view == "scope" or view == "tasks" or view == "ownership": 1 else: 3
	if view == "modules": return model.modules_view(entity)
	if view == "overview": return ok(overview_tree(model.overview()))
	if view == "types": return model.types_view(entity, depth)
	if view == "ownership": return model.ownership_view(entity, depth)
	if view == "flow" or view == "scope" or view == "tasks": return model.flow_view(
		view,
		entity,
		depth,
	)

	roots := model.view_roots(view, entity)?
	var builder = ViewBuilder(view: view.clone(), depth: depth)
	var root = plain(f"{view.upper()} VIEW")

	for f in roots:
		if builder.count >= NODE_CAP:
			builder.skipped += 1
			continue

		var path = Set[String]()
		root.children.append(builder.expand(model, f, 0, path))

	if roots.is_empty(): root.children.append(plain("none"))
	root.cap(builder.skipped)
	return ok(root)

// ---- Class diagrams and ownership flows ----

fn mermaid_text(text: String) String: text.replace("[", "~").replace("]", "~")

fn class_id(f: Fact) String: sanitize(f.name, true)

fn Model.class_set(entity: String, depth: Int) List[Fact]?:
	var out = List[Fact]()

	if entity.is_empty():
		for f in self.facts.entities:
			if is_data_type(f): out.append(f.clone())
		return out

	start := self.find_entity(entity).get_or(empty_fact())
	if start.key.is_empty() or not is_data_type(start): return none

	var seen = Set[String]()
	seen.add(start.key.clone())
	out.append(start.clone())

	var frontier = [start.clone()]

	for _level in 0..depth:
		var next = List[Fact]()

		for f in frontier:
			for s in f.slots:
				for key in s.refs:
					t := self.get(key)
					if t.key.is_empty(): continue
					if seen.contains(t.key): continue

					seen.add(t.key.clone())
					out.append(t.clone())
					next.append(t.clone())

		frontier = next

	return out

fn Model.class_diagram(entity: String, depth: Int) String?:
	all := self.class_set(entity, depth)?
	chosen := all.take(NODE_CAP)

	// Names are labels, not declaration identities. Reserve every existing name before
	// allocating IDs so a generated ID cannot collide with a later declaration's name.
	var reserved = Set[String]()
	for f in chosen: reserved.add(class_id(f))

	var assigned = Set[String]()
	var ids = Map[String, String]()
	var next_id = 0

	for f in chosen:
		name := class_id(f)

		if not assigned.contains(name):
			assigned.add(name.clone())
			ids.add(f.key.clone(), name.clone())
		else:
			var id = f"__ms_type_{next_id}"
			next_id += 1

			while reserved.contains(id):
				id = f"__ms_type_{next_id}"
				next_id += 1

			reserved.add(id.clone())
			ids.add(f.key.clone(), id)

	var out = "classDiagram\n"

	for f in chosen:
		id := ids.get_or(f.key, "")
		name := class_id(f)

		if id == name: out = out.concat(f"    class {id} \{\n")
		else: out = out.concat(f"    class {id}[\"{name}\"] \{\n")

		if f.kind != "type": out = out.concat(f"        <<{f.kind}>>\n")

		for s in f.slots:
			if f.kind == "type": out = out.concat(
				f"        +{mermaid_text(s.ty)} {s.name}\n"
			)
			else: out = out.concat(f"        {s.name}{mermaid_text(s.ty)}\n")

		out = out.concat("    }\n")

	for f in chosen:
		for s in f.slots:
			for key in s.refs:
				if target := ids.get(key):
					out = out.concat(
						f"    {ids.get_or(f.key, "")} *-- {target} : {s.name}\n"
					)
	return out

fn Model.ownership_roots(entity: String) List[Fact]:
	if not entity.is_empty():
		found := self.find_entity(entity).get_or(empty_fact())
		if not found.key.is_empty(): return [found]

	return ownership_candidates(self)

fn flow_type_node(var out: String, var declared: List[String], ty: String) String:
	id := f"t_{sanitize(ty, false)}"

	if not declared.contains(id):
		out = out.concat(f"    {id}([\"{ty.replace("\"", "'")}\"])\n")
		declared.append(id.clone())

	return id

fn style_for(mode: String) String:
	if mode == "var": return "stroke:#d33,stroke-width:3px"
	if mode == "copy": return "stroke:#999,stroke-dasharray:4"
	if mode == "move": return "stroke:#2a2,stroke-width:3px"

	return "stroke:#37b"

// Render checked parameter/result modes without inferring ownership from type
// spellings.
fn Model.ownership_flow(entity: String, depth: Int) String:
	roots := self.ownership_roots(entity)
	var out = "flowchart LR\n"
	var styles = List[String]()
	var declared = List[String]()
	var frontier = roots.take(NODE_CAP)
	var done = List[String]()

	for level in 0..depth + 1:
		var next = List[Fact]()

		for f in frontier:
			if done.contains(f.key): continue

			done.append(f.key.clone())

			fid := f"f{done.length()}"
			closes := if f.scopes > 0: f"<br/>closes {f.scopes}" else: ""
			out = out.concat(
				f"    {fid}[\"{f.name.replace("\"", "'")}(){closes}\"]:::fn\n"
			)

			if not f.receiver.is_empty():
				tid := flow_type_node(out, declared, "self")
				out = out.concat(f"    {tid} -->|\"self {f.receiver}\"| {fid}\n")

				if f.receiver == "var": styles.append("stroke:#d33,stroke-width:3px")
				else if f.receiver == "move": styles.append(
					"stroke:#2a2,stroke-width:3px"
				)
				else: styles.append("stroke:#37b")

			for s in f.slots:
				mode := slot_mode(s)
				tid := flow_type_node(out, declared, s.ty)
				out = out.concat(
					f"    {tid} -->|\"{f"{s.name} {mode}".trim_end()}\"| {fid}\n"
				)
				styles.append(style_for(mode))

			if r := f.result:
				tid := flow_type_node(out, declared, r.ty)
				out = out.concat(f"    {fid} -->|\"{f.result_ownership}\"| {tid}\n")

				if f.result_borrow: styles.append("stroke:#37b")
				else: styles.append("stroke:#2a2,stroke-width:3px")

			if level < depth:
				for key in f.calls:
					if callee := self.fact(key): next.append(callee)

		frontier = next

	out = out.concat("    classDef fn fill:#fff3cd,stroke:#b8860b\n")
	for i in 0..styles.length(): out = out.concat(f"    linkStyle {i} {styles[i]}\n")
	return out

fn ascii_classes(model: Model, all: List[Fact]) String:
	chosen := all.take(NODE_CAP)
	var out = ""

	for f in chosen:
		tag := if f.kind == "type": "" else: f"<<{f.kind}>> "
		title := f"{tag}{f.name}"
		var members = List[String]()

		for s in f.slots:
			if f.kind == "type": members.append(f"{s.name}: {s.ty}")
			else: members.append(f"{s.name}{s.ty}")

		var width = title.length()
		for m in members: width = width.max(m.length())

		rule := f"+-{"-".repeat(width)}-+\n"
		out = out.concat(rule)
		out = out.concat(f"| {title.pad_end(width, " ")} |\n")

		if not members.is_empty():
			out = out.concat(rule)
			for m in members: out = out.concat(f"| {m.pad_end(width, " ")} |\n")

		out = out.concat(rule)
		for s in f.slots:
			for key in s.refs:
				if t := model.fact(key):
					if chosen.any(fn c: c.key == t.key): out = out.concat(
						f"  <>-- {s.name} --> {t.name}\n"
					)
		out = out.concat("\n")

	if chosen.is_empty(): out = out.concat("none\n")
	return out

type SignatureWriter:
	depth: Int
	lines: Int = 0
	out: String = ""

// One signature line per function: `var` marks an argument the callee may change.
// Callees nest beneath their caller.
fn var SignatureWriter.write(
	model: Model,
	f: Fact,
	level: Int,
	var path: List[String],
) Void:
	var params = List[String]()

	if f.receiver == "borrow": params.append("self")
	else if not f.receiver.is_empty(): params.append(f"{f.receiver} self")

	for s in f.slots:
		var_text := if s.exclusive: "var " else: ""
		params.append(f"{var_text}{s.name}: {s.ty}")

	var result = ""
	if r := f.result: result = r.ty.clone()

	closes := if f.scopes > 0: f"  [closes {f.scopes}]" else: ""
	self.out = (
		self
		.out
		.concat(
			f"{"  ".repeat(level)}{f.name}({params.join(", ")}) {result}{closes}\n"
		)
	)
	self.lines += 1
	if level >= self.depth: return

	path.append(f.key.clone())

	for key in f.calls:
		callee := model.get(key)
		if callee.key.is_empty(): continue
		if path.contains(key) or self.lines >= NODE_CAP: continue

		self.write(model, callee, level + 1, path)

	void path.pop()

fn Model.ascii_ownership(entity: String, depth: Int) String:
	var writer = SignatureWriter(depth: depth)
	var path = List[String]()

	for f in self.ownership_roots(entity):
		if writer.lines >= NODE_CAP:
			writer.out = (
				writer
				.out
				.concat(f"+more (output capped at {NODE_CAP} lines)\n")
			)
			break

		writer.write(self, f, 0, path)

	if writer.lines == 0: writer.out = writer.out.concat("none\n")
	return writer.out

// Mermaid output with its own diagram type: a class diagram for `types`, a color-coded
// flow for `ownership`. Other views use the generic tree rendering (none).
export fn mermaid_view(model: Model, view: String, entity: String, depth: Int) String?:
	if view == "overview": return overview_mermaid(model.overview())
	if view == "types": return model.class_diagram(entity, if depth <= 0: 3 else: depth)
	if view == "ownership": return model.ownership_flow(
		entity,
		if depth <= 0: 1 else: depth,
	)

	return none

// Plain-text counterpart of the Mermaid diagrams.
export fn ascii_view(model: Model, view: String, entity: String, depth: Int) String?:
	if view == "overview": return overview_ascii(model.overview())

	if view == "types":
		chosen := model.class_set(entity, if depth <= 0: 3 else: depth)?
		return ascii_classes(model, chosen)

	if view == "ownership": return model.ascii_ownership(
		entity,
		if depth <= 0: 1 else: depth,
	)

	return none

// ---- Tree renderings ----

fn write_children(var out: String, children: List[Node], prefix: String) Void:
	for i in 0..children.length():
		last := i + 1 == children.length()
		connector := if last: "`- " else: "|- "
		next := if last: "   " else: "|  "
		out = out.concat(f"{prefix}{connector}{children[i].label}\n")
		write_children(out, children[i].children, f"{prefix}{next}")

// The tree with fixed connectors.
export fn tree_ascii(root: Node) String:
	var out = f"{root.label}\n"
	write_children(out, root.children, "")
	return out

fn mermaid_label(label: String) String:
	return label.replace("&", "&amp;").replace("\"", "&quot;").replace(
		"<",
		"&lt;",
	).replace(">", "&gt;")

fn mermaid_into(var out: String, node: Node, var count: Int) String:
	id := f"n{count}"
	count += 1
	out = out.concat(f"    {id}[\"{mermaid_label(node.label)}\"]\n")

	for child in node.children:
		child_id := mermaid_into(out, child, count)
		out = out.concat(f"    {id} --> {child_id}\n")

	return id

// The same tree as a flowchart; node names are pre-order numbers.
export fn tree_mermaid(root: Node) String:
	var out = "flowchart TD\n"
	var count = 0
	void mermaid_into(out, root, count)
	return out

fn pad_json(depth: Int) String: "  ".repeat(depth)

fn node_json(node: Node, depth: Int) String:
	inner := pad_json(depth + 1)
	var out = "{\n"
	out = out.concat(f"{inner}\"label\": {json_string(node.label)},\n")
	out = out.concat(f"{inner}\"kind\": {json_string(node.kind)},\n")
	out = out.concat(f"{inner}\"reference\": {json_string(node.reference)},\n")
	out = out.concat(f"{inner}\"file\": {json_string(node.file)},\n")
	out = out.concat(f"{inner}\"line\": {node.line},\n")
	out = out.concat(f"{inner}\"omitted\": {node.omitted},\n")

	if node.children.is_empty(): out = out.concat(f"{inner}\"children\": []\n")
	else:
		out = out.concat(f"{inner}\"children\": [\n")

		for i in 0..node.children.length():
			out = out.concat(
				f"{pad_json(depth + 2)}{node_json(node.children[i], depth + 2)}"
			)
			if i + 1 < node.children.length(): out = out.concat(",")
			out = out.concat("\n")

		out = out.concat(f"{inner}]\n")

	return out.concat(f"{pad_json(depth)}\}")

export fn tree_json(view: String, entity: String, tree: Node) String:
	return f"\{\n  \"format\": 1,\n  \"view\": {json_string(view)},\n  \"entity\": {json_string(entity)},\n  \"tree\": {node_json(tree, 1)}\n\}\n"

// ---- Entry ----

// The text `ms diagram --view VIEW` prints: the view's own rendering when it has one.
export fn render(
	model: Model,
	view: String,
	entity: String,
	depth: Int,
	format: String,
) String!:
	tree := build_view(model, view, entity, depth)?
	if format == "json": return ok(tree_json(view, entity, tree))

	if format == "mermaid":
		if text := mermaid_view(model, view, entity, depth): return ok(text)
		return ok(tree_mermaid(tree))

	if text := ascii_view(model, view, entity, depth): return ok(text)

	return ok(tree_ascii(tree))

fn views_tool() Command:
	return Command(
		name: "views.ms",
		about: "Render one view of a facts file",
		args: [
			Arg("facts", help: "The facts JSON"),
			Arg("view", help: "The view name"),
			Arg("entity", required: false),
			Arg("depth", required: false, kind: FlagKind.Int),
			Arg("format", required: false, help: "ascii, mermaid or json"),
		],
	)

// ms: allow_effect std.fs.read
// ms: allow_effect std.console.write
fn show(m: Matches) Void!:
	facts := parse[Facts](read_file(m.string("facts")).wait()?.decode_utf8().get_or(""))?
	text := render(
		model_of(facts),
		m.string("view"),
		m.string_or_none("entity").get_or(""),
		m.int_or_none("depth").get_or(0),
		m.string_or_none("format").get_or("ascii"),
	)?
	var out = stdout()
	out.write(text)?
	out.flush()?
	return ok()

fn main() Int:
	return run_tool(views_tool(), show)
