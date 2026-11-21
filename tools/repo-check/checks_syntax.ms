// Repository checks that read the syntax tree of Manuscript sources (the canonical dump
// over libms, see sexp.ms): the standard library parses, no nested `match`,
// stream-shaped names,
// `impl` adjacency and optional defaults.
import (
	list from "@std/os/fs.ms",

	Kind, Sexp, parse_tree, syntax_dump from "./sexp.ms",
	check_shrinking, list_lines, read_text, skipped from "./util.ms",
)

// ---- reading declarations ----

// Top-level `(decl ...)` nodes of a module.
fn top_decls(tree: Sexp) List[Int]:
	var out = List[Int]()
	for node in tree.children[0]:
		if tree.head(node) == "decl": out.append(node)
	return out

// Field `n` of a declaration, counting from the name: `extern fn` prints as two atoms,
// which shifts every later field by one.
fn field(tree: Sexp, decl: Int, n: Int) Int:
	shift := if tree.word(tree.child(decl, 2)) == "extern": 1 else: 0
	return tree.child(decl, 3 + shift + n)

fn kind_of(tree: Sexp, decl: Int) String: tree.word(tree.child(decl, 2))

fn name_of(tree: Sexp, decl: Int) String: tree.word(field(tree, decl, 0))

fn is_exported(tree: Sexp, decl: Int) Bool: tree.word(field(tree, decl, 1)) == "true"

// The line in a position atom `line:column:offset`.
fn line_of(tree: Sexp, node: Int) Int:
	return tree.word(tree.child(node, 1)).split(":")[0].parse_int().get_or(0)

fn methods_of(tree: Sexp, decl: Int) List[Int]:
	return tree.children[field(tree, decl, 8)].clone()

fn params_of(tree: Sexp, decl: Int) List[Int]:
	return tree.children[field(tree, decl, 9)].clone()

// A type node's name; "" for `nil`.
fn type_name(tree: Sexp, node: Int) String:
	if node < 0 or tree.kind[node] != Kind.Paren: return ""
	return tree.word(tree.child(node, 2))

fn receiver_name(tree: Sexp, decl: Int) String: type_name(tree, field(tree, decl, 12))

fn contract_name(tree: Sexp, decl: Int) String: type_name(tree, field(tree, decl, 11))

// Declarations of the three kinds that name a type.
fn is_type_kind(kind: String) Bool: kind == "type" or kind == "alternative"

fn parsed_stdlib(files: List[String]) Map[String, Sexp]:
	var out = Map[String, Sexp]()

	for path in files:
		if not path.starts_with("src/stdlib/") or not path.ends_with(".ms"): continue

		if source := read_text(path):
			if tree := parse_tree(path, source): out.add(path.clone(), tree)

	return out

// ---- every standard-library declaration file must parse ----

// The `.ms` files directly under `src/stdlib/`, sorted.
fn stdlib_files() List[String]:
	var paths = List[String]()
	if entries := list("src/stdlib"):
		for entry in entries:
			if not entry.directory and entry.name.ends_with(".ms"): paths.append(
				f"src/stdlib/{entry.name}"
			)
	paths.sort()
	return paths

export fn standard_syntax() List[String]:
	var issues = List[String]()

	for path in stdlib_files():
		if source := read_text(path):
			dump := syntax_dump(path, source)
			if dump.starts_with("error "):
				issues.append(
					f"invalid standard-library syntax: {path}: {dump.lines()[0]}"
				)
		else:
			issues.append(f"{path}: cannot read as UTF-8 text")

	return issues

// ---- the nested-match ban over `.ms` files and fenced Markdown snippets ----

ALLOWANCE := "// manuscript:allow-nested-match "

// A written `match` (not the Bool match an `if` expression stands for): an `expr` node
// of kind
// `match` whose first arm starts after the expression itself.
fn is_written_match(tree: Sexp, node: Int) Bool:
	if tree.head(node) != "expr" or tree.word(tree.child(node, 2)) != "match": return false

	arms := tree.children[tree.children[node].last().get_or(-1)]
	if arms.is_empty(): return false

	return tree.word(tree.child(arms[0], 1)) != tree.word(tree.child(node, 1))

// Lines of matches that sit inside another match's arms.
fn nested_match_lines(tree: Sexp) List[Int]:
	var lines = List[Int]()

	for node in 0..tree.size():
		if not is_written_match(tree, node): continue

		var up = tree.parent[node]

		while up >= 0:
			if is_written_match(tree, up):
				lines.append(line_of(tree, node))
				break

			up = tree.parent[up]

	return lines

// A line and the bodies of ```manuscript, ```ms and
// ```text fences, with their first line.
fn fences(source: String) List[Fence]:
	var found = List[Fence]()
	var open = false
	var start = 0
	var body = List[String]()
	var index = 0

	for line in source.lines():
		index += 1

		if not open:
			if line == "```manuscript" or line == "```ms" or line == "```text":
				open = true
				start = index + 1
				body = []
		else if line == "```":
			found.append(Fence(line: start, code: body.join("\n") + "\n"))
			open = false
		else:
			body.append(line.clone())

	return found

type Fence:
	line: Int
	code: String

fn indent_of(line: String) Int: line.length() - line.trim_start().length()

// Reference fragments may consist solely of executable statements: wrap them in a
// function.
fn wrapped_fragment(code: String) String:
	var indent = -1

	for line in code.lines():
		if line.trim().is_empty(): continue

		if indent < 0 or indent_of(line) < indent: indent = indent_of(line)

	if indent < 0: indent = 0

	var body = List[String]()

	for line in code.lines():
		if line.length() >= indent:
			body.append("    " + line.slice(indent, line.length()))
		else:
			body.append("    " + line)

	return "fn fragment() Void:\n" + body.join("\n") + "\n"

fn report_nested(
	path: String,
	code: String,
	first_line: Int,
	fixture: Bool,
) List[String]:
	var issues = List[String]()
	var wrapped = false
	var tree = parse_tree(path, code)

	if no_decls(tree):
		wrapped = true
		tree = parse_tree(path, wrapped_fragment(code))

	if parsed := tree:
		lines := code.lines()

		for line in nested_match_lines(parsed):
			within := line - (if wrapped: 1 else: 0)
			var allowed = false
			if fixture and within >= 2 and within - 2 < lines.length():
				if reason := lines[within - 2].trim().cut_prefix(ALLOWANCE):
					allowed = not reason.trim().is_empty()
			if not allowed:
				issues.append(
					f"{path}:{first_line + within - 1}: nested match; flatten the outer match with an early exit, a compatible trailing ?, or a small helper"
				)

	return issues

fn no_decls(tree: Sexp?) Bool:
	if parsed := tree: return top_decls(parsed).is_empty()
	return true

export fn nested(files: List[String]) List[String]:
	var issues = List[String]()

	for path in files:
		if skipped(path): continue

		is_ms := path.ends_with(".ms")
		if not is_ms and not path.ends_with(".md"): continue

		source := read_text(path).get_or("")
		if source.is_empty(): continue

		if is_ms:
			issues.extend(report_nested(path, source, 1, path.starts_with("tests/")))
		else:
			for fence in fences(source):
				issues.extend(report_nested(path, fence.code, fence.line, false))

	return issues

// ---- stream-shaped names ----

STREAM_MODULES := [
	"src/stdlib/io/io.ms", "src/stdlib/io/streams.ms", "src/stdlib/io/steps.ms",
	"src/stdlib/io/forward.ms"
]
BANNED_STREAM_NAMES := ["next", "receive", "feed", "write_bytes"]
STREAM_ALLOWED := "tools/repo-check/stream-names-allowed.txt"

fn banned_methods(
	tree: Sexp,
	owner: String,
	methods: List[Int],
	var found: List[String],
) Void:
	for method in methods:
		name := name_of(tree, method)
		if BANNED_STREAM_NAMES.contains(name): found.append(f"{owner}.{name}")

fn exported_types(tree: Sexp, include_interfaces: Bool) Set[String]:
	var names = Set[String]()

	for decl in top_decls(tree):
		kind := kind_of(tree, decl)
		if not is_exported(tree, decl): continue

		if is_type_kind(kind) or (include_interfaces and kind == "interface"):
			names.add(name_of(tree, decl))

	return names

// `Type.method` entries for exported methods with a stream-shaped name.
fn stream_entries(tree: Sexp) List[String]:
	exported := exported_types(tree, true)
	var found = List[String]()

	for decl in top_decls(tree):
		kind := kind_of(tree, decl)

		if (
			kind == "interface"
			and is_exported(tree, decl)
			and name_of(tree, decl) != "Iterator"
		):
			banned_methods(tree, name_of(tree, decl), methods_of(tree, decl), found)
		else if kind == "impl":
			owner := receiver_name(tree, decl)
			if exported.contains(owner) and contract_name(tree, decl) != "Iterator":
				banned_methods(tree, owner, methods_of(tree, decl), found)

	return found

export fn stream_names(files: List[String]) List[String]:
	var found = List[String]()
	trees := parsed_stdlib(files)

	for path in trees.keys():
		if STREAM_MODULES.contains(path): continue

		for entry in stream_entries(trees.get_or(path, Sexp())): found.append(
			f"{path} {entry}"
		)

	return check_shrinking(
		list_lines(read_text(STREAM_ALLOWED).get_or("")),
		found,
		fn path,
		entry: f"{path}: exported `{entry}` has a stream-shaped name; return a ReadStream[T] or take a WriteStream[T] instead (see proposals/stream-redesign.md)",
		fn entry: f"{STREAM_ALLOWED}: `{entry}` no longer exists; delete the line"
	)

// ---- `impl` must directly follow its type ----

export fn impl_adjacency(files: List[String]) List[String]:
	var issues = List[String]()
	trees := parsed_stdlib(files)

	for path in trees.keys():
		tree := trees.get_or(path, Sexp())
		local := exported_or_local_types(tree)
		var previous = ""

		for decl in top_decls(tree):
			kind := kind_of(tree, decl)

			if is_type_kind(kind):
				previous = name_of(tree, decl)
			else if kind == "impl":
				name := receiver_name(tree, decl)
				if local.contains(name) and previous != name:
					issues.append(
						f"{path}:{line_of(tree, decl)}: `impl` for `{name}` must directly follow `{name}` or another impl of it"
					)
				previous = name
			else:
				previous = ""

	return issues

fn exported_or_local_types(tree: Sexp) Set[String]:
	var names = Set[String]()
	for decl in top_decls(tree):
		if is_type_kind(kind_of(tree, decl)): names.add(name_of(tree, decl))
	return names

// ---- optional parameters carry defaults ----

OPTIONAL_ALLOWED := "tools/repo-check/optional-defaults-allowed.txt"

// `owner.function parameter` entries for parameters of `func` that are optional or an options
// type and have no default.
fn undefaulted(tree: Sexp, owner: String, func: Int, var found: List[String]) Void:
	name := name_of(tree, func)
	function := if owner.is_empty(): name else: f"{owner}.{name}"

	for param in params_of(tree, func):
		default := tree.child(param, 4)
		if default >= 0 and tree.kind[default] == Kind.Paren: continue

		pname := tree.word(tree.child(param, 2))
		optional := type_name(tree, tree.child(param, 3)) == "Optional"
		if optional or pname == "options" or pname == "limits": found.append(
			f"{function} {pname}"
		)

export fn optional_defaults(files: List[String]) List[String]:
	var found = List[String]()
	trees := parsed_stdlib(files)

	for path in trees.keys():
		if path.starts_with("src/stdlib/internal/"): continue

		tree := trees.get_or(path, Sexp())
		exported := exported_types(tree, false)
		var entries = List[String]()

		for decl in top_decls(tree):
			kind := kind_of(tree, decl)

			if kind == "fn" and is_exported(tree, decl):
				undefaulted(tree, "", decl, entries)
			else if kind == "interface" and is_exported(tree, decl):
				for method in methods_of(tree, decl): undefaulted(
					tree,
					name_of(tree, decl),
					method,
					entries,
				)
			else if kind == "impl" and exported.contains(receiver_name(tree, decl)):
				for method in methods_of(tree, decl): undefaulted(
					tree,
					receiver_name(tree, decl),
					method,
					entries,
				)

		for entry in entries: found.append(f"{path} {entry}")

	return check_shrinking(
		list_lines(read_text(OPTIONAL_ALLOWED).get_or("")),
		found,
		fn path,
		entry: f"{path}: `{entry}` is optional or an options type with no default; add `= none` or `= Options()` so callers never pass it explicitly",
		fn entry: f"{OPTIONAL_ALLOWED}: `{entry}` no longer needs an exception; delete the line"
	)
