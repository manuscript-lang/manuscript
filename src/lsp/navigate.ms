// Hover and go-to-definition over the checker's facts (analysis.ms). Everything here is
// offsets into the document text; the server turns them into positions.
import (
	expect_equal, expect_ok, expect_some from "@std/test/test.ms",

	Facts, NodeFact, RES_BINDING, RES_SYMBOL, analyze from "./analysis.ms",
)

// A byte range of the document.
export type Span:
	start: Int
	end: Int

export type Hover:
	text: String
	span: Span

// The node with the smallest span around `offset` that satisfies `wanted`.
fn narrowest(facts: Facts, offset: Int, wanted: fn(NodeFact) Bool) NodeFact?:
	var best: NodeFact? = none
	var width = -1

	for node in facts.nodes:
		if node.end <= node.start or offset < node.start or offset >= node.end: continue
		if not wanted(node): continue

		if width < 0 or node.end - node.start < width:
			width = node.end - node.start
			best = node.clone()

	return best

fn has_type(node: NodeFact) Bool:
	return node.type_text != ""

fn is_reference(node: NodeFact) Bool:
	return node.kind == RES_BINDING or node.kind == RES_SYMBOL or node.callee >= 0

// The type of the expression under `offset`, with the name the source writes there.
export fn hover(facts: Facts, source: String, offset: Int) Hover?:
	node := narrowest(facts, offset, has_type)?
	written := source.view(node.start, node.end)
	return Hover(text: f"{written}: {node.type_text}", span: Span(node.start, node.end))

// Where the name that `offset` is on is declared, when that is in this document.
export fn definition(facts: Facts, source: String, offset: Int) Span?:
	node := narrowest(facts, offset, is_reference)?

	if node.kind == RES_BINDING:
		binding := facts.bindings[node.target]
		return Span(binding.offset, binding.offset + binding.name.length())

	var callee = node.target
	if node.callee >= 0: callee = node.callee

	for symbol in facts.symbols:
		if symbol.id != callee or not symbol.local: continue

		// The declaration starts at its keyword; the name follows it.
		at := (
			symbol.offset
			+ source.view(symbol.offset, source.length()).index_of(
				symbol.name
			)?
		)
		return Span(at, at + symbol.name.length())

	return none

test "hover names the type of a local and definition finds where it was bound":
	source := "fn main() Int:\n\tcount := 1\n\treturn count\n"
	facts := analyze(source) | expect_ok?
	use := 20 + source.view(20, source.length()).index_of("count").get()
	shown := hover(facts, source, use) | expect_some?
	expect_equal(shown.text, "count: Int")?

	found := definition(facts, source, use) | expect_some?
	expect_equal(source.view(found.start, found.end), "count")?
	expect_equal(found.start < use, true)?

test "definition follows a call to the function declared in the document":
	source := "fn double(n: Int) Int:\n\treturn n + n\n\nfn main() Int:\n\treturn double(4)\n"
	facts := analyze(source) | expect_ok?
	call := source.index_of("double(4)").get()
	found := definition(facts, source, call + 1) | expect_some?
	expect_equal(found.start, 3)?
