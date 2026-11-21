import (
	working_directory from "@std/os/env.ms",
	expect_equal from "@std/test/test.ms",
)

// What the C checker knows about one document, read through `ms_tool_analyze` (libms,
// compiler/include/ms/tool.h). A program that imports this module links `libmstool.a`.
// Facts are keyed by the syntax-node ids of a parse of the same text, so hover and
// definition join them to the tree's positions. A document that imports a project
// module is not covered yet (`Uncovered`).
extern type Analysis

extern fn ms_tool_analyze(path: String, text: String, overlay: List[String]) Analysis

extern fn ms_tool_analysis_status(analysis: Analysis) Int

extern fn ms_tool_analysis_message(analysis: Analysis) String

extern fn ms_tool_analysis_rows(analysis: Analysis) List[Int]

extern fn ms_tool_analysis_names(analysis: Analysis) List[String]

// How a name resolved: MsResolution in compiler/include/ms/facts.h.
export RES_BINDING := 1
export RES_SYMBOL := 2
export RES_FIELD := 3
export RES_CASE := 4
export RES_METHOD := 5

// A node the checker resolved or typed. `target` is a binding, symbol, field, case or
// method id by `kind`; types are source text, empty when unknown.
export type NodeFact:
	id: Int
	kind: Int
	target: Int
	type_text: String
	written_type: String
	// The symbol a call expression calls, -1 when it is not a call of a declared
	// function.
	callee: Int
	// Byte offsets of the node's text.
	start: Int
	end: Int

export type BindingFact:
	name: String
	type_text: String
	node: Int
	line: Int
	column: Int
	offset: Int
	role: Int
	flags: Int
	reads: Int

// A declaration some name resolved to, in this document or the standard library.
export type SymbolFact:
	id: Int
	name: String
	kind: Int
	module: String
	local: Bool
	exported: Bool
	node: Int
	offset: Int
	line: Int
	column: Int
	type_text: String

export type Facts:
	nodes: List[NodeFact]
	bindings: List[BindingFact]
	symbols: List[SymbolFact]

export enum AnalyzeError:
	Syntax(message: String)
	Uncovered(message: String)

fn text_of(names: List[String], at: Int) String:
	if at < 0: return ""
	return names[at].clone()

// Checks `text` as a module of its own.
export fn analyze(text: String) Facts!AnalyzeError:
	return analyze_in("", text, [])

// Checks `text` as the module at `path`; `overlay` holds the other open buffers as
// path, text, path, text, ...
export fn analyze_in(
	path: String,
	text: String,
	overlay: List[String],
) Facts!AnalyzeError:
	analysis := ms_tool_analyze(path, text, overlay)
	status := ms_tool_analysis_status(analysis)
	if status == 1:
		return error(AnalyzeError.Syntax(ms_tool_analysis_message(analysis)))
	if status == 2:
		return error(AnalyzeError.Uncovered(ms_tool_analysis_message(analysis)))

	rows := ms_tool_analysis_rows(analysis)
	names := ms_tool_analysis_names(analysis)
	var facts = Facts([], [], [])
	if rows.is_empty(): return ok(facts)

	var at = 3

	for row in 0..rows[0]:
		facts.nodes.append(
			NodeFact(
				rows[at],
				rows[at + 1],
				rows[at + 2],
				text_of(names, rows[at + 3]),
				text_of(names, rows[at + 4]),
				rows[at + 5],
				0,
				0,
			)
		)
		at += 6

	for row in 0..rows[1]:
		facts.bindings.append(
			BindingFact(
				text_of(names, rows[at]),
				text_of(names, rows[at + 1]),
				rows[at + 2],
				rows[at + 3],
				rows[at + 4],
				rows[at + 5],
				rows[at + 6],
				rows[at + 7],
				rows[at + 8],
			)
		)
		at += 9

	for row in 0..rows[2]:
		facts.symbols.append(
			SymbolFact(
				rows[at],
				text_of(names, rows[at + 1]),
				rows[at + 2],
				text_of(names, rows[at + 3]),
				rows[at + 4] == 1,
				rows[at + 5] == 1,
				rows[at + 6],
				rows[at + 7],
				rows[at + 8],
				rows[at + 9],
				text_of(names, rows[at + 10]),
			)
		)
		at += 11

	// Past the ownership rows (moved names, then resources) and the effect rows come
	// the node spans.
	at += rows[at] + 1
	at += rows[at] * 3 + 1
	at += rows[at + 1] * 4 + 2

	for index in 0..facts.nodes.length():
		facts.nodes[index].start = rows[at]
		facts.nodes[index].end = rows[at + 1]
		at += 2

	return ok(facts)

test "the checker types a local and resolves its use":
	source := "fn main() Int:\n\tcount := 1\n\treturn count\n"
	parsed := analyze(source)
	expect_equal(parsed.is_error(), false)?

	facts := parsed.get()
	var found = false

	for b in facts.bindings:
		if b.name == "count":
			expect_equal(b.type_text, "Int")?
			found = true

	expect_equal(found, true)?

	var uses = 0
	for n in facts.nodes:
		if n.kind == RES_BINDING:
			uses += 1
	expect_equal(uses >= 1, true)?

test "a call resolves to the function declared in the document":
	source := "fn double(n: Int) Int:\n\treturn n + n\n\nfn main() Int:\n\treturn double(4)\n"
	parsed := analyze(source)
	expect_equal(parsed.is_error(), false)?

	facts := parsed.get()
	var found = false
	for s in facts.symbols:
		if s.name == "double" and s.local and s.type_text == "fn(Int) Int":
			found = true

	var calls = 0
	for n in facts.nodes:
		if n.callee >= 0:
			calls += 1
	expect_equal(calls, 1)?
	expect_equal(found, true)?

test "a syntax error and a project import are reported, not analysed":
	broken := analyze("fn (:")
	expect_equal(broken.is_error(), true)?

	project := analyze(
		"import (\n\tother from \"./other.ms\",\n)\n\nfn main() Int:\n\treturn 0\n"
	)
	expect_equal(project.is_error(), true)?

test "a project import is analysed from an unsaved buffer":
	// Tests run in the test file's directory, which exists; the two buffers are not on
	// disk.
	dir := working_directory()?
	helper := "export fn twice(n: Int) Int:\n\treturn n + n\n"
	entry := "import (\n\ttwice from \"./unsaved_helper.ms\",\n)\n\nfn main() Int:\n\treturn twice(2)\n"
	parsed := analyze_in(
		f"{dir}/unsaved_main.ms",
		entry,
		[f"{dir}/unsaved_helper.ms", helper],
	)
	expect_equal(parsed.is_error(), false)?

	facts := parsed.get()
	var found = false
	for s in facts.symbols:
		if s.name == "twice" and not s.local:
			found = true
	expect_equal(found, true)?
