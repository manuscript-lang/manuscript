// What the C checker resolved in one module, read through `ms_tool_analyze` (libms,
// compiler/include/ms/tool.h) and keyed by the syntax-node ids of a parse of the same
// text (`Syntax.id`). A program that imports this module links `libmstool.a`. A module
// that imports a project module is not covered yet, so it has no analysis.
//
// This reads the same rows as tools/lsp/analysis.ms, which a project cannot import (an
// import may not leave its project root); the lint rules need only the call and symbol
// rows, so only those are kept. Removal condition: tools/lsp and tools/ms share one
// project root, then both import one reader (#5248).
import expect_equal, expect_some from "@std/test/test.ms"

extern type Analysis

extern fn ms_tool_analyze(text: String) Analysis

extern fn ms_tool_analysis_status(analysis: Analysis) Int

extern fn ms_tool_analysis_rows(analysis: Analysis) List[Int]

extern fn ms_tool_analysis_names(analysis: Analysis) List[String]

NODE_WIDTH := 6
BINDING_WIDTH := 9
SYMBOL_WIDTH := 11

export type Analyzed:
	// The symbol a call expression calls, by node id; absent when it calls no declared
	// function.
	callee: Map[Int, Int] = Map[Int, Int]()
	// The type of an expression as source reads it, by node id; absent when unknown.
	types: Map[Int, String] = Map[Int, String]()
	// The node id of the declaration each symbol names, by symbol id.
	declared: Map[Int, Int] = Map[Int, Int]()

// The analysis of `text`; none when it does not parse or is not covered yet.
export fn analyze(text: String) Analyzed?:
	analysis := ms_tool_analyze(text)
	if ms_tool_analysis_status(analysis) != 0: return none

	rows := ms_tool_analysis_rows(analysis)
	names := ms_tool_analysis_names(analysis)
	var found = Analyzed()
	if rows.is_empty(): return found

	var at = 3

	for _row in 0..rows[0]:
		id := rows[at]
		if rows[at + 5] >= 0: found.callee.add(id, rows[at + 5])
		if rows[at + 3] >= 0: found.types.add(id, names[rows[at + 3]].clone())
		at += NODE_WIDTH

	at += rows[1] * BINDING_WIDTH

	for _row in 0..rows[2]:
		found.declared.add(rows[at], rows[at + 6])
		at += SYMBOL_WIDTH

	return found

test "a call resolves to the function it calls":
	found := analyze("fn g(n: Int) Int:\n    return g(n - 1)\n") | expect_some?
	found.callee.is_empty() | expect_equal(expected: false)?
	found.declared.is_empty() | expect_equal(expected: false)?
