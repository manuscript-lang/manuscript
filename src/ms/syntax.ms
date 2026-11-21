// The C parser's tables, read through `extern fn` (src/compiler/include/ms/tool.h is
// the other half of this contract). A tool links `libmstool.a`:
// `ms run tool.ms --link libmstool.a`.

// One token: the kind index into `token_kinds()`, the byte range in the CRLF-normalised
// text, and start and end positions in original-source coordinates.
export type Token:
	kind: Int
	lo: Int
	hi: Int
	offset: Int
	line: Int
	column: Int
	end_offset: Int
	end_line: Int
	end_column: Int

export enum LexError:
	Failed(code: Int, message: String)

extern fn ms_tool_lex(text: String) List[Int]!LexError

extern fn ms_tool_token_kinds() List[String]

fn token_width() Int: 9

// The token kind names, such as "NAME", "STRING", "(" and "fn", indexed by
// `Token.kind`.
export fn token_kinds() List[String]:
	return ms_tool_token_kinds()

// The index of the kind named `name`, or -1.
export fn token_kind(name: String) Int:
	kinds := ms_tool_token_kinds()
	for i in 0..kinds.length():
		if kinds[i] == name: return i
	return -1

// Lexes `text`; an error holds the first lexical error's message and byte offset.
export fn lex(text: String) List[Token]!LexError:
	flat := ms_tool_lex(text)?
	width := token_width()
	var tokens = List[Token]()
	var at = 0

	while at < flat.length():
		tokens.append(
			Token(
				kind: flat[at],
				lo: flat[at + 1],
				hi: flat[at + 2],
				offset: flat[at + 3],
				line: flat[at + 4],
				column: flat[at + 5],
				end_offset: flat[at + 6],
				end_line: flat[at + 7],
				end_column: flat[at + 8],
			)
		)
		at += width

	return ok(tokens)

// ---- syntax trees ----

export extern type Tree

extern fn ms_tool_parse(text: String) Tree

extern fn ms_tool_tree_error(tree: Tree) String

extern fn ms_tool_tree_error_offset(tree: Tree) Int

extern fn ms_tool_tree_error_line(tree: Tree) Int

extern fn ms_tool_tree_error_column(tree: Tree) Int

extern fn ms_tool_tree_nodes(tree: Tree) List[Int]

extern fn ms_tool_tree_names(tree: Tree) List[String]

extern fn ms_tool_node_kinds() List[String]

extern fn ms_tool_keywords() List[String]

fn node_width() Int: 12

// The node kind names the C encoder uses ("Fn", "Bind", "Binary", ...), indexed by
// `Syntax.kind`.
export fn node_kinds() List[String]:
	return ms_tool_node_kinds()

// The reserved words, in alphabetical order.
export fn keywords() List[String]:
	var words = ms_tool_keywords()
	words.sort()
	return words

// The index of the node kind named `name`, or -1.
export fn node_kind(name: String) Int:
	kinds := ms_tool_node_kinds()
	for i in 0..kinds.length():
		if kinds[i] == name: return i
	return -1

// A first syntax error.
export type SyntaxError:
	message: String
	offset: Int
	line: Int
	column: Int

// A parsed module as parallel columns, one entry per node in preorder (so a node's
// index is its position in the table, and its children are the nodes after it linked
// through `first` and
// `next`). `flags`, `a` and `b` mean what src/compiler/include/ms/tool.h says for the node's kind: `a`
// and `b` index `names` or are -1. Absent optional children are `None` nodes.
export type Syntax:
	kind: List[Int]
	id: List[Int]
	offset: List[Int]
	line: List[Int]
	column: List[Int]
	end_offset: List[Int]
	end_line: List[Int]
	end_column: List[Int]
	flags: List[Int]
	a: List[Int]
	b: List[Int]
	count: List[Int]
	first: List[Int]
	next: List[Int]
	names: List[String]

// Parses `text`; the error is the first syntax error.
export fn parse(text: String) Syntax!SyntaxError:
	tree := ms_tool_parse(text)
	message := ms_tool_tree_error(tree)
	if not message.is_empty():
		return error(
			SyntaxError(
				message: message,
				offset: ms_tool_tree_error_offset(tree),
				line: ms_tool_tree_error_line(tree),
				column: ms_tool_tree_error_column(tree),
			)
		)

	return ok(decode(ms_tool_tree_nodes(tree), ms_tool_tree_names(tree)))

fn decode(flat: List[Int], names: List[String]) Syntax:
	width := node_width()
	total := flat.length() / width
	var tree = Syntax(
		kind: [0].repeated(total),
		id: [0].repeated(total),
		offset: [0].repeated(total),
		line: [0].repeated(total),
		column: [0].repeated(total),
		end_offset: [0].repeated(total),
		end_line: [0].repeated(total),
		end_column: [0].repeated(total),
		flags: [0].repeated(total),
		a: [0].repeated(total),
		b: [0].repeated(total),
		count: [0].repeated(total),
		first: [-1].repeated(total),
		next: [-1].repeated(total),
		names: names,
	)

	// Open nodes and, for each, its last child so far and how many children are still
	// to come.
	var open = List[Int]()
	var last = List[Int]()
	var left = List[Int]()

	for i in 0..total:
		base := i * width
		tree.kind[i] = flat[base]
		tree.id[i] = flat[base + 1]
		tree.offset[i] = flat[base + 2]
		tree.line[i] = flat[base + 3]
		tree.column[i] = flat[base + 4]
		tree.end_offset[i] = flat[base + 5]
		tree.end_line[i] = flat[base + 6]
		tree.end_column[i] = flat[base + 7]
		tree.flags[i] = flat[base + 8]
		tree.a[i] = flat[base + 9]
		tree.b[i] = flat[base + 10]
		tree.count[i] = flat[base + 11]

		if open.length() > 0:
			top := open.length() - 1
			parent := open[top]

			if tree.first[parent] < 0: tree.first[parent] = i
			else: tree.next[last[top]] = i

			last[top] = i
			left[top] -= 1

		if tree.count[i] > 0:
			open.append(i)
			last.append(-1)
			left.append(tree.count[i])

		while open.length() > 0 and left[open.length() - 1] == 0:
			void open.pop()
			void last.pop()
			void left.pop()

	return tree

// The children of node `at`, in order.
export fn children(tree: Syntax, at: Int) List[Int]:
	var out = List[Int]()
	var child = tree.first[at]

	while child >= 0:
		out.append(child)
		child = tree.next[child]

	return out
