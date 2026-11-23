// The standard-library rules of `make repo-check` (tools/repo-check.ms), read from the
// declaration files in stdlib/ by their shape, not by a full parse:
//   - option parameters: an exported function never requires a caller to write `Options()`, so a parameter
//     named `options` or `limits` declares a default; a `T?` parameter defaults to `null` on its own
//     (stdlib/internal is extern glue);
//   - stream names: no exported type has a method named `next`, `receive`, `feed` or `write_bytes` outside the
//     stream modules, because anything that yields values over time is a ReadStream or WriteStream;
//   - adjacency: the methods of a type follow its declaration or another method of the same type;
//   - internal externs: every `extern fn` in stdlib/internal is named by another standard-library file.
// optional-defaults-allowed.txt and stream-names-allowed.txt list what predates a rule;
// they only shrink.
import read_file from "@std/os/fs.ms"

stream_modules := [
	"stdlib/io/io.ms", "stdlib/io/streams.ms", "stdlib/io/steps.ms",
	"stdlib/io/forward.ms"
]
banned_methods := ["next", "receive", "feed", "write_bytes"]
type_words := ["type", "enum", "interface", "namespace"]

fn text_of(path: String) String:
	if bytes := read_file(path).wait(): return bytes.decode_utf8().get_or("").replace(
		"\r\n",
		"\n",
	)
	return ""

fn is_identifier(c: String) Bool:
	return (
		(c >= "a" and c <= "z")
		or (c >= "A" and c <= "Z")
		or (c >= "0" and c <= "9")
		or c == "_"
	)

// `text` without a leading word of `words` and the space after it, repeated.
fn without_words(text: String, words: List[String]) String:
	var rest = text.clone()
	var again = true

	while again:
		again = false

		for word in words:
			if rest.starts_with(f"{word} "):
				rest = rest.slice(word.length() + 1, rest.length())
				again = true

	return rest

// The identifier at the start of `text`.
fn leading_name(text: String) String:
	var end = 0

	for c in text.chars():
		if not is_identifier(c): break

		end += 1

	return text.slice(0, end)

// One declared function: where it sits, who owns it and the text of its parameters.
type Declared:
	line: Int
	exported: Bool
	owner: String
	name: String
	params: List[String]

// The parameters between the parentheses of `header`, split at top-level commas.
fn parameters(header: String) List[String]:
	var found = List[String]()
	open := header.index_of("(").get_or(-1)
	if open < 0: return found

	var depth = 0
	var current = ""
	var closed = false

	for c in header.slice(open, header.length()).chars():
		if closed: break

		if c == "(" or c == "[" or c == "{":
			depth += 1
			if depth == 1: continue
		else if c == ")" or c == "]" or c == "}":
			depth -= 1

			if depth == 0:
				closed = true
				continue
		else if c == "," and depth == 1:
			found.append(current.trim())
			current = ""
			continue

		current = f"{current}{c}"

	if current.trim() != "": found.append(current.trim())
	return found

// A function header from the line at `start`, continued over following lines until its
// parentheses close.
fn header_from(lines: List[String], start: Int) String:
	var text = ""
	var depth = 0
	var opened = false
	var at = start

	while at < lines.length():
		line := lines[at].clone()
		text = f"{text} {line.trim()}"

		for c in line.chars():
			if c == "(":
				depth += 1
				opened = true
			else if c == ")": depth -= 1

		if opened and depth <= 0: break

		at += 1

	return text.trim()

// The declared name `Type.method` or `name` of a header that starts after `fn `.
fn declared_of(
	line: Int,
	exported: Bool,
	after_fn: String,
	owner_override: String,
	params_from: String,
) Declared:
	qualified := leading_name(after_fn)
	var owner = owner_override.clone()
	var name = qualified.clone()
	dot := after_fn.index_of(".").get_or(-1)

	if owner_override == "" and dot > 0 and dot == qualified.length():
		owner = qualified.clone()
		name = leading_name(after_fn.slice(dot + 1, after_fn.length()))

	return Declared(
		line: line,
		exported: exported,
		owner: owner,
		name: name,
		params: parameters(params_from),
	)

// Every function a file declares: free and `fn Type.method` at column 0, and the
// methods of its interfaces.
fn declarations(text: String) List[Declared]:
	lines := text.split("\n")
	var found = List[Declared]()
	var interface_name = ""
	var interface_exported = false
	var at = 0

	while at < lines.length():
		line := lines[at].clone()
		trimmed := line.trim()

		if line.starts_with("\t") and interface_name != "":
			rest := without_words(trimmed.clone(), ["var", "move"])

			if rest.starts_with("fn "):
				after := rest.slice(3, rest.length())
				found.append(
					declared_of(
						at + 1,
						interface_exported,
						after,
						interface_name.clone(),
						header_from(lines.clone(), at),
					)
				)
		else if (
			line != ""
			and not line.starts_with("\t")
			and not line.starts_with("//")
		):
			interface_name = ""

			exported := line.starts_with("export ")
			rest := without_words(line.clone(), ["export", "opaque", "extern"])

			if rest.starts_with("interface "):
				interface_name = leading_name(rest.slice(10, rest.length()))
				interface_exported = exported
			else if line.contains("extern fn ") or rest.starts_with("fn "):
				after := without_words(
					rest.slice(
						rest.index_of("fn ").get_or(0) + 3,
						rest.length(),
					),
					["var", "move"],
				)
				found.append(
					declared_of(
						at + 1,
						exported,
						after,
						"",
						header_from(lines.clone(), at),
					)
				)

		at += 1

	return found

// The names a file declares as types, interfaces or enums, and which of them it
// exports.
fn type_names(text: String, only_exported: Bool) List[String]:
	var found = List[String]()

	for line in text.split("\n"):
		if line.starts_with("\t") or line.starts_with("//"): continue

		exported := line.starts_with("export ")
		if only_exported and not exported: continue

		rest := without_words(line.clone(), ["export", "opaque", "extern"])
		for word in type_words:
			if rest.starts_with(f"{word} "): found.append(
				leading_name(
					rest.slice(word.length() + 1, rest.length())
				)
			)

	return found

// ---- allow lists that only shrink ----

fn allow_list(path: String) List[String]:
	var entries = List[String]()
	for line in text_of(path).split("\n"):
		if line != "" and not line.starts_with("//"): entries.append(line.trim())
	return entries

// Findings not on the allow list, and allow-list lines that no longer match anything.
fn shrinking(
	allowed: List[String],
	found: List[String],
	list_path: String,
	describe: String,
) List[String]:
	var issues = List[String]()
	for entry in found:
		if not allowed.contains(entry): issues.append(f"{entry}: {describe}")
	for entry in allowed:
		if not found.contains(entry): issues.append(
			f"{list_path}: `{entry}` no longer needs an exception; delete the line"
		)
	return issues

// ---- the four rules ----

fn param_name(param: String) String:
	colon := param.index_of(":").get_or(-1)
	if colon < 0: return param.trim()

	words := param.slice(0, colon).trim().split(" ")
	return words.last().get_or("").clone()

fn has_default(param: String) Bool:
	return param.contains(" = ")

fn optional_defaults(
	path: String,
	declared: List[Declared],
	exported_types: List[String],
) List[String]:
	var found = List[String]()

	for d in declared:
		visible := if d.owner == "": d.exported else: exported_types.contains(d.owner)
		if not visible: continue

		function := if d.owner == "": d.name.clone() else: f"{d.owner}.{d.name}"

		for param in d.params:
			if has_default(param.clone()): continue

			name := param_name(param.clone())
			if name == "options" or name == "limits": found.append(
				f"{path} {function} {name}"
			)

	return found

fn stream_names(
	path: String,
	declared: List[Declared],
	exported_types: List[String],
) List[String]:
	var found = List[String]()

	for d in declared:
		if d.owner == "" or d.owner == "Iterator": continue
		if not exported_types.contains(d.owner): continue

		if banned_methods.contains(d.name): found.append(f"{path} {d.owner}.{d.name}")

	return found

// Methods that do not follow their type or another method of it.
fn adjacency(path: String, text: String) List[String]:
	var issues = List[String]()
	local := type_names(text, false)
	var previous = ""
	var line_number = 0
	var in_comment = false

	for line in text.split("\n"):
		line_number += 1

		if in_comment:
			if line.contains("*/"): in_comment = false
			continue

		if line.starts_with("/*"):
			in_comment = not line.contains("*/")
			continue

		if line == "" or line.starts_with("\t") or line.starts_with("//"): continue
		if line.starts_with(")") or line.starts_with("]") or line.starts_with("}"): continue

		rest := without_words(line.clone(), ["export", "opaque", "extern"])
		var named = ""
		for word in type_words:
			if rest.starts_with(f"{word} "): named = leading_name(
				rest.slice(word.length() + 1, rest.length())
			)

		if named != "":
			previous = named
			continue

		method := without_words(rest.clone(), ["fn", "var", "move"])
		owner := leading_name(method.clone())
		dot := method.index_of(".").get_or(-1)

		if rest.starts_with("fn ") and dot > 0 and dot == owner.length():
			if local.contains(owner) and previous != owner: issues.append(
				f"{path}:{line_number}: method of `{owner}` must directly follow `{owner}` or another method of it"
			)
			previous = owner.clone()
			continue

		previous = ""

	return issues

fn contains_word(text: String, word: String) Bool:
	var from = 0

	while from <= text.length():
		rest := text.slice(from, text.length())
		at := rest.index_of(word).get_or(-1)
		if at < 0: return false

		start := from + at
		before := if start > 0: text.slice(start - 1, start) else: ""
		after := text.slice(start + word.length(), start + word.length() + 1)
		if (
			(before == "" or not is_identifier(before))
			and (after == "" or not is_identifier(after))
		): return true

		from = start + 1

	return false

fn internal_externs(sources: Map[String, String]) List[String]:
	var issues = List[String]()

	for path in sources.keys():
		if not path.starts_with("stdlib/internal/"): continue

		for line in sources[path].split("\n"):
			rest := without_words(line.trim(), ["export"])
			if not rest.starts_with("extern fn "): continue

			name := leading_name(rest.slice(10, rest.length()))
			var used = false
			for other in sources.keys():
				if (
					other != path
					and contains_word(
						sources[other].clone(),
						name.clone(),
					)
				): used = true
			if not used: issues.append(
				f"{path}: `extern fn {name}` is not used by any other standard-library file; delete it and its native side"
			)

	return issues

// Every problem the four rules find in the tracked standard-library declaration files.
export fn stdlib_issues(files: List[String]) List[String]:
	var sources = Map[String, String]()
	for path in files:
		if path.starts_with("stdlib/") and path.ends_with(".ms"): sources[path.clone()] = text_of(
			path.clone()
		)

	var optional_found = List[String]()
	var stream_found = List[String]()
	var issues = List[String]()
	if sources.length() == 0: issues.append(
		f"no stdlib/*.ms file was found among {files.length()} listed files (first: `{files.first().get_or("")}`)"
	)

	for path in sources.keys():
		text := sources[path].clone()
		declared := declarations(text.clone())
		exported_types := type_names(text.clone(), true)
		if not path.starts_with("stdlib/internal/"): optional_found = optional_found.concat(
			optional_defaults(
				path.clone(),
				declared.clone(),
				exported_types.clone(),
			)
		)
		if not stream_modules.contains(path): stream_found = stream_found.concat(
			stream_names(path.clone(), declared, exported_types)
		)
		issues = issues.concat(adjacency(path.clone(), text))

	issues = issues.concat(
		shrinking(
			allow_list("tools/optional-defaults-allowed.txt"),
			optional_found,
			"tools/optional-defaults-allowed.txt",
			"is an options parameter with no default; add `= Options()` so callers never pass it explicitly",
		)
	)
	issues = issues.concat(
		shrinking(
			allow_list("tools/stream-names-allowed.txt"),
			stream_found,
			"tools/stream-names-allowed.txt",
			"has a stream-shaped name; return a ReadStream[T] or take a WriteStream[T] instead (see proposals/stream-redesign.md)",
		)
	)
	return issues.concat(internal_externs(sources))
