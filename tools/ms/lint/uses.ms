// How a name is used in a subtree, read off the syntax table by spelling: shared by the
// rules that rewrite a variable. A name passed to a call counts as written, so a
// doubtful case is never reported.
import (
	Syntax, children, node_kind from "../syntax.ms",
	Analyzed from "./analysis.ms",
)

// The identifier a node names (`a` is its name index).
export fn spelling(tree: Syntax, at: Int) String:
	return tree.names[tree.a[at]].clone()

// How many times the name `name` is spelled in the subtree at `at`.
export fn mentions(tree: Syntax, at: Int, name: String) Int:
	var total = if tree.kind[at] == node_kind("Name") and spelling(tree, at) == name: 1 else: 0
	for child in children(tree, at): total += mentions(tree, child, name)
	return total

// Whether the subtree at `at` assigns the name or passes it to a call, which may change
// it.
export fn may_write(tree: Syntax, at: Int, name: String) Bool:
	node := tree.kind[at]
	if (
		node == node_kind("Assign")
		and tree.flags[at] % 2 == 0
		and spelling(tree, at) == name
	):
		return true

	if node == node_kind("Call"):
		for argument in children(tree, children(tree, at)[1]):
			value := children(tree, argument)[0]
			if tree.kind[value] == node_kind("Name") and spelling(tree, value) == name: return true

	for child in children(tree, at):
		if may_write(tree, child, name): return true
	return false

// Whether the subtree at `at` calls anything.
export fn has_call(tree: Syntax, at: Int) Bool:
	if tree.kind[at] == node_kind("Call"): return true

	for child in children(tree, at):
		if has_call(tree, child): return true
	return false

// The index of the node with id `id`, -1 when there is none.
fn node_of(tree: Syntax, id: Int) Int:
	for at in 0..tree.id.length():
		if tree.id[at] == id and tree.kind[at] != node_kind("None"): return at
	return -1

// Whether argument number `index` (`argument` is its node) of the call `call` is a
// `var` parameter of the function the checker resolved. A call it did not resolve
// changes nothing; with no analysis at all every argument counts as changed.
fn argument_changes(
	tree: Syntax,
	call: Int,
	index: Int,
	argument: Int,
	facts: Analyzed?,
) Bool:
	if facts.is_none(): return true

	symbol := facts.get().callee.get_or(tree.id[call], -1)
	declared := facts.get().declared.get_or(symbol, -1)
	node := if declared < 0: -1 else: node_of(tree, declared)
	if node < 0: return false

	var params_at = -1
	if tree.kind[node] == node_kind("Fn"): params_at = 1
	if tree.kind[node] == node_kind("Method"): params_at = 3
	if params_at < 0: return false

	params := children(tree, children(tree, node)[params_at])
	var chosen = if index < params.length(): index else: -1

	if tree.flags[argument] % 2 == 1:
		chosen = -1
		for at in 0..params.length():
			if tree.a[params[at]] == tree.a[argument]: chosen = at

	return chosen >= 0 and tree.flags[params[chosen]] % 2 == 1

// Like `may_write`, but a name passed to a call counts as written only when that
// argument is a `var` parameter of the resolved function.
export fn changed_in(tree: Syntax, at: Int, name: String, facts: Analyzed?) Bool:
	node := tree.kind[at]
	if (
		node == node_kind("Assign")
		and tree.flags[at] % 2 == 0
		and spelling(tree, at) == name
	):
		return true

	if node == node_kind("Call"):
		arguments := children(tree, children(tree, at)[1])

		for index in 0..arguments.length():
			value := children(tree, arguments[index])[0]
			if (
				tree.kind[value] == node_kind("Name")
				and spelling(tree, value) == name
				and argument_changes(
					tree,
					at,
					index,
					arguments[index],
					facts,
				)
			):
				return true

	for child in children(tree, at):
		if changed_in(tree, child, name, facts): return true
	return false
