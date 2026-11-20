// A reader for the canonical syntax-tree dump (`ms_tool_syntax_dump`, over libms):
// lists in parentheses or brackets, atoms and quoted strings, held in flat arrays
// indexed by node.
import ms_tool_syntax_dump from "./libms.ms"

export enum Kind:
	Paren
	Bracket
	Atom
	Text

export type Sexp:
	kind: List[Kind] = []
	text: List[String] = []
	parent: List[Int] = []
	children: List[List[Int]] = []

// The node count; node 0 is the bracket list of the top-level forms.
fn Sexp.size() Int: self.kind.length()

fn var Sexp.add_node(kind: Kind, text: String, parent: Int) Int:
	index := self.kind.length()
	self.kind.append(kind)
	self.text.append(text)
	self.parent.append(parent)
	self.children.append([])

	if parent >= 0:
		var siblings = self.children[parent].clone()
		siblings.append(index)
		self.children.set(parent, siblings)

	return index

fn is_space(byte: UInt8) Bool: byte == 32 or byte == 10 or byte == 9 or byte == 13

// Reads dump text. A line that is not a form (`omitted []`, `nodes 158`) is read as
// atoms and lists too; callers look at the top-level forms they know.
export fn read_sexp(text: String) Sexp:
	var tree = Sexp()
	data := text.as_bytes()
	size := data.length()
	var current = tree.add_node(Kind.Bracket, "", -1)
	var at = 0

	while at < size:
		byte := data.get(at)

		if is_space(byte):
			at += 1
		else if byte == 40 or byte == 91:
			kind := if byte == 40: Kind.Paren else: Kind.Bracket
			current = tree.add_node(kind, "", current)
			at += 1
		else if byte == 41 or byte == 93:
			if tree.parent[current] >= 0: current = tree.parent[current]
			at += 1
		else if byte == 34:
			var end = at + 1

			while end < size and data.get(end) != 34:
				if data.get(end) == 92: end += 1
				end += 1

			tree.add_node(Kind.Text, text.slice(at + 1, end), current)
			at = end + 1
		else:
			var end = at
			while (
				end < size
				and not is_space(data.get(end))
				and data.get(end) != 41
				and data.get(end) != 93
			):
				end += 1
			tree.add_node(Kind.Atom, text.slice(at, end), current)
			at = end

	return tree

// The dump of `source`: a tree, or an `error ...` line, or empty when it is not valid
// UTF-8.
export fn syntax_dump(path: String, source: String) String:
	return ms_tool_syntax_dump(path, source)

// The tree of `source`, or none when it does not parse.
export fn parse_tree(path: String, source: String) Sexp?:
	dump := ms_tool_syntax_dump(path, source)
	if dump.is_empty() or dump.starts_with("error "): return none

	return read_sexp(dump)

// Node `index`'s text when it is an atom or string, else "".
fn Sexp.word(index: Int) String:
	if self.kind[index] == Kind.Atom or self.kind[index] == Kind.Text: return (
		self
		.text[index]
		.clone()
	)
	return ""

// Child `n` of node `index`, or -1.
fn Sexp.child(index: Int, n: Int) Int:
	kids := self.children[index]
	if n < kids.length(): return kids[n]

	return -1

// The first atom of a list node: its head (`decl`, `expr`, `type`).
fn Sexp.head(index: Int) String:
	if self.kind[index] != Kind.Paren: return ""

	first := self.child(index, 0)
	if first < 0: return ""

	return self.word(first)
