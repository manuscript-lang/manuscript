// Source spans of expressions, shared by the rules that edit the text.
import (
	Bytes from "@std/bytes.ms",

	Syntax, children from "../syntax.ms",
)

// Whether the brackets of `text` pair up.
export fn balanced(text: Bytes) Bool:
	var open = 0

	for at in 0..text.length():
		byte := text[at]

		if byte == 40 or byte == 91 or byte == 123: open += 1
		else if byte == 41 or byte == 93 or byte == 125: open -= 1

		if open < 0: return false

	return open == 0

// Where the expression at `at` begins: its own position is an operator or a name for
// the kinds that lead with an operand, so take the leftmost of its subtree. Records
// with no position (an absent child, a text part) carry offset 0 and are skipped.
export fn first_offset(tree: Syntax, at: Int) Int:
	var first = tree.offset[at]

	for child in children(tree, at):
		from := first_offset(tree, child)
		if from > 0 and from < first: first = from

	return first

// The furthest end offset of any expression in the subtree at `at`.
export fn last_offset(tree: Syntax, at: Int) Int:
	var last = tree.end_offset[at]

	for child in children(tree, at):
		to := last_offset(tree, child)
		if to > last: last = to

	return last

// The source text between `from` and `to` when it can stand alone in an edit: its
// brackets pair up and it is on one line; none otherwise.
export fn span(source: Bytes, from: Int, to: Int) String?:
	if from < 0 or to > source.length() or from > to: return none

	piece := source.view(from, to)
	if not balanced(piece): return none

	for at in 0..piece.length():
		if piece[at] == 10: return none
	return piece.decode_utf8()
