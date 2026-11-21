// What the C checker resolved in one module, read through `ms_tool_analyze` (libms,
// src/compiler/include/ms/tool.h) and keyed by the syntax-node ids of a parse of the
// same text (`Syntax.id`). A program that imports this module links `libmstool.a`. A
// module that imports a project module is not covered yet, so it has no analysis.
//
// This reads the same rows as src/lsp/analysis.ms, which a project cannot import (an
// import may not leave its project root); the lint rules need only the call and symbol
// rows, so only those are kept. Removal condition: src/lsp and src/ms share one
// project root, then both import one reader (#5248).
import expect_equal, expect_some from "@std/test/test.ms"

extern type Analysis

extern fn ms_tool_analyze(path: String, text: String, overlay: List[String]) Analysis

extern fn ms_tool_analysis_status(analysis: Analysis) Int

extern fn ms_tool_analysis_rows(analysis: Analysis) List[Int]

extern fn ms_tool_analysis_names(analysis: Analysis) List[String]

NODE_WIDTH := 6
BINDING_WIDTH := 9
SYMBOL_WIDTH := 11
RESOURCE_WIDTH := 3
REACH_WIDTH := 4
CONFLICT_WIDTH := 8
// MS_RES_BINDING: a name that resolves to a local, parameter or pattern name.
BINDING_RESOLUTION := 1

export type Analyzed:
	// The symbol a call expression calls, by node id; absent when it calls no declared
	// function.
	callee: Map[Int, Int] = Map[Int, Int]()
	// The type of an expression as source reads it, by node id; absent when unknown.
	types: Map[Int, String] = Map[Int, String]()
	// The node id of the declaration each symbol names, by symbol id.
	declared: Map[Int, Int] = Map[Int, Int]()
	// The binding a name expression reads or writes, by node id.
	bound: Map[Int, Int] = Map[Int, Int]()
	// The name nodes that move a value out, by node id.
	moves: Map[Int, Bool] = Map[Int, Bool]()
	// The bindings that are closed when their scope ends.
	resources: List[Resource] = []
	// The effects a function reaches that no `allow_effect` line permits (MSL116).
	effects: List[Reach] = []
	// Whether the effect scan saw every callable it reached, so no violation is
	// missing.
	reach_complete: Bool = false
	// The capitalised match payload names that coincide with a type or a case (MSL106).
	conflicts: List[Conflict] = []

// A function that reaches an effect it does not permit: where the reference that brings
// the effect in is, and what `ms lint` says about it.
export type Reach:
	offset: Int
	line: Int
	column: Int
	message: String

// A capitalised payload name that still binds a fresh value: the arm, where the name is
// written, what it coincides with, the payload's type and, when the payload is the enum
// that owns the case, the nested pattern the name would have to be.
export type Conflict:
	arm: Int
	offset: Int
	line: Int
	column: Int
	identity: String
	payload: String
	nested: String
	// The type an arm of a match over an interface value names, "" for any other arm.
	contract: String

// A binding the scope closes (a resource): where it is introduced and what its type
// offers.
export type Resource:
	binding: Int
	// The node that introduces the binding (the pattern of its `let`).
	decl: Int
	name: String
	offset: Int
	line: Int
	column: Int
	// Whether the ownership pass followed the function, so `moves` is complete for it.
	followed: Bool
	// A `flush` or `commit` method taking nothing and returning a Result, "" for none.
	finisher: String

// The name at `at`, "" for -1.
fn optional_name(names: List[String], at: Int) String:
	if at < 0: return ""
	return names[at].clone()

// The analysis of `text`; none when it does not parse or is not covered yet.
export fn analyze(text: String) Analyzed?:
	// No path: the module stands alone, and one that imports a project module is not
	// covered.
	analysis := ms_tool_analyze("", text, [])
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
		if rows[at + 1] == BINDING_RESOLUTION: found.bound.add(id, rows[at + 2])
		at += NODE_WIDTH

	var bindings = List[Resource]()

	for _row in 0..rows[1]:
		bindings.append(
			Resource(
				binding: bindings.length(),
				decl: rows[at + 2],
				name: names[rows[at]].clone(),
				offset: rows[at + 5],
				line: rows[at + 3],
				column: rows[at + 4],
				followed: false,
				finisher: "",
			)
		)
		at += BINDING_WIDTH

	for _row in 0..rows[2]:
		found.declared.add(rows[at], rows[at + 6])
		at += SYMBOL_WIDTH

	for index in 0..rows[at]: found.moves.add(rows[at + 1 + index], true)
	at += rows[at] + 1

	for index in 0..rows[at]:
		first := at + 1 + index * RESOURCE_WIDTH
		var resource = bindings[rows[first]].clone()
		resource.followed = rows[first + 1] == 1
		if rows[first + 2] >= 0: resource.finisher = names[rows[first + 2]].clone()
		found.resources.append(resource)

	at += rows[at] * RESOURCE_WIDTH + 1
	found.reach_complete = rows[at] == 1

	for index in 0..rows[at + 1]:
		first := at + 2 + index * REACH_WIDTH
		found.effects.append(
			Reach(
				offset: rows[first],
				line: rows[first + 1],
				column: rows[first + 2],
				message: names[rows[first + 3]].clone(),
			)
		)

	// The span of each node row follows the effect rows: two offsets per node.
	at += 2 + rows[at + 1] * REACH_WIDTH + 2 * rows[0]

	for index in 0..rows[at]:
		first := at + 1 + index * CONFLICT_WIDTH
		found.conflicts.append(
			Conflict(
				arm: rows[first],
				offset: rows[first + 1],
				line: rows[first + 2],
				column: rows[first + 3],
				identity: names[rows[first + 4]].clone(),
				payload: names[rows[first + 5]].clone(),
				nested: optional_name(names, rows[first + 6]),
				contract: optional_name(names, rows[first + 7]),
			)
		)

	return found

test "a call resolves to the function it calls":
	found := analyze("fn g(n: Int) Int:\n    return g(n - 1)\n") | expect_some?
	found.callee.is_empty() | expect_equal(expected: false)?
	found.declared.is_empty() | expect_equal(expected: false)?
