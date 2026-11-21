// `ms search_symbol` over the standard-library API model: the index, module, declaration
// and member pages of crates/ms-tooling/src/guide/pages.rs, the fuzzy ranking of
// guide/search.rs, `name_rank` of crates/ms-lsp/src/query.rs, and the rendering of
// crates/ms-cli/src/engine/search.rs. Project declarations arrive with the C checker;
// until then `project_total` is 0 and only library matches appear.
//
// The model is built by the C checker (`ms_tool_api_model`, compiler/src/check/api_model.c), which
// checks the embedded standard library; compiler/tests/api-model-diff.sh holds it byte for byte to
// the JSON the Rust `ms-tooling` example `api_model` prints.
//   ms run tools/ms/search.ms --link target/c-tool/libmstool.a -- [--json] [--limit N] [name or words...]
import (
	Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	is_alphabetic, is_lowercase, is_numeric, is_uppercase from "@std/unicode.ms",

	run_tool, tree_tool from "./cli.ms",
	Declaration, Member, Module, indent, json_string, string_array from "./docgen.ms",
)

type Model:
	modules: List[Module]

extern fn ms_tool_api_model() String

// ---- Names and text helpers ----

fn short_name(path: String) String:
	stripped := path.cut_prefix("@std/").get_or(path)
	name := stripped.cut_suffix(".ms").get_or(stripped)
	if slash := name.last_index_of("/"): return name.slice(slash + 1, name.length())

	return name.clone()

fn package_name(path: String) String:
	stripped := path.cut_prefix("@std/").get_or(path)
	return stripped.cut_suffix(".ms").get_or(stripped)

// `group_by[K: Hashable]` becomes `group_by`.
fn bare(name: String) String:
	if open := name.index_of("["): return name.slice(0, open)
	return name.clone()

fn std_path(module_path: String, name: String) String: f"{short_name(module_path)}.{bare(name)}"

fn take_chars(text: String, count: Int) String:
	var out = ""
	var taken = 0

	for ch in text.chars():
		if taken >= count: break

		out = out.concat(ch)
		taken += 1

	return out

fn squash(text: String) String: text.fields().join(" ")

// One line of at most `limit` scalars.
fn one_line(text: String, limit: Int) String:
	joined := squash(text)
	body := joined.cut_suffix(":").get_or(joined).trim()
	if body.scalar_length() > limit: return take_chars(body, limit - 1).concat("…")

	return body

// The first non-empty line of a doc, cut at a word boundary.
fn first_line(doc: String, limit: Int) String:
	for raw in doc.split("\n"):
		line := squash(raw)
		if line.is_empty(): continue
		if line.scalar_length() <= limit: return line

		head := take_chars(line, limit - 1)
		var cut = -1
		if space := head.last_index_of(" "): cut = space
		if cut < limit / 2: cut = limit - 1
		return take_chars(line, cut.min(line.scalar_length())).concat("…")

	return ""

// At most `limit` bytes of `doc`, dropping 20 scalars at a time as the Rust code does.
fn cap_doc(text: String, limit: Int) String:
	doc := text.trim()
	if doc.length() <= limit: return doc

	var kept = doc.scalar_length()
	var out = doc.clone()

	while out.length() > limit:
		kept = (kept - 20).max(0)
		out = take_chars(doc, kept)

	return out.concat("…")

fn clip_lines(text: String, limit: Int) String:
	lines := text.split("\n")
	if lines.length() <= limit: return text.clone()

	var out = ""

	for i in 0..limit:
		if i > 0: out = out.concat("\n")
		out = out.concat(lines[i])

	return out.concat("\n...")

// Keeps the head and tail of long text. A cut inside a scalar becomes U+FFFD, as the
// Rust code's lossy decoding makes it.
fn clip_text(text: String, limit: Int) String:
	if text.length() <= limit: return text.clone()

	room := (limit - 48).max(0)
	head := room * 2 / 3
	tail := room / 3
	start := text.length() - tail
	var head_text = ""
	var tail_text = ""
	var offset = 0

	for ch in text.chars():
		width := ch.length()

		if offset + width <= head: head_text = head_text.concat(ch)
		else if offset < head: head_text = head_text.concat("\u{fffd}")

		if offset >= start: tail_text = tail_text.concat(ch)
		else if offset + width > start:
			for _stray in 0..offset + width - start: tail_text = tail_text.concat(
				"\u{fffd}"
			)

		offset += width

	omitted := text.length() - head - tail
	return f"{head_text}\n[... {omitted} bytes omitted ...]\n{tail_text}"

fn floor_boundary(text: String, limit: Int) Int:
	var offset = 0

	for ch in text.chars():
		width := ch.length()
		if offset + width > limit: break

		offset += width

	return offset

fn debug_quote(text: String) String:
	var out = "\""

	for ch in text.chars():
		if ch == "\"": out = out.concat("\\\"")
		else if ch == "\\": out = out.concat("\\\\")
		else if ch == "\n": out = out.concat("\\n")
		else if ch == "\t": out = out.concat("\\t")
		else if ch == "\r": out = out.concat("\\r")
		else: out = out.concat(ch)

	return out.concat("\"")

// ---- Pages ----

fn is_prelude(module: Module) Int: if module.path == "prelude": 0 else: 1

fn compare_modules(a: Module, b: Module) Int:
	order := is_prelude(a).compare(is_prelude(b))
	if order != 0: return order

	return a.path.compare(b.path)

// The standard modules, `prelude` first and the rest by path.
fn sorted_modules(modules: List[Module]) List[Module]:
	var all = modules.clone()
	all.sort(compare_modules)
	return all

fn module_names(modules: List[Module]) List[String]:
	var names = List[String]()
	for module in modules: names.append(short_name(module.path))
	return names

fn pad_name(text: String, width: Int) String:
	if text.length() >= width: return text.clone()
	return text.concat(" ".repeat(width - text.length()))

fn index_lines(modules: List[Module], width: Int) String:
	var out = ""

	for module in modules:
		var line = pad_name(short_name(module.path), 12)
		var shown = 0

		for d in module.declarations:
			next := f"{line} {d.name},"
			if next.length() > width and shown > 0: break

			line = next
			shown += 1

		if line.ends_with(","): line = line.slice(0, line.length() - 1)

		rest := module.declarations.length() - shown
		if rest > 0: line = f"{line} +{rest}"
		out = f"{out}{line}\n"

	return out

fn index(modules: List[Module]) String:
	header := "Standard modules (prelude needs no import).\n`ms search_symbol <module>` lists one, `ms search_symbol <module>.<Name>` shows a declaration, `ms search_symbol <words>` searches.\n\n"
	var width = 84

	while true:
		body := index_lines(modules, width)
		if header.length() + body.length() <= 3400 or width <= 24: return f"{header}{body}"

		width -= 4

	return ""

fn import_line(module: Module) String:
	if module.path == "prelude": return "available in every module; no import"
	return f"import Name from {debug_quote(module.path)}"

fn module_page(module: Module) String:
	var out = f"{module.path}: {import_line(module)}\n"

	for i in 0..module.declarations.length():
		d := module.declarations[i]

		if i == 45:
			out = f"{out}... {module.declarations.length() - 45} more; narrow with `ms search_symbol <words>`\n"
			break

		if d.kind == "fn" and not d.declaration.is_empty():
			out = f"{out}{one_line(d.declaration, 150)}\n"
			continue

		opaque := if d.opaque: "opaque " else: ""
		out = f"{out}{opaque}{d.kind} {bare(d.name)}"

		doc := first_line(d.doc, 90)
		if not doc.is_empty(): out = f"{out} // {doc}"
		out = f"{out}\n"

	out = f"{out}Details: ms search_symbol {short_name(module.path)}.<Name>\n"
	return clip_text(out, 3500)

fn declaration_page(module: Module, d: Declaration) String:
	opaque := if d.opaque: "opaque " else: ""
	var out = f"{opaque}{d.kind} {d.name} ({module.path})\n"
	if module.path != "prelude": out = f"{out}import {bare(d.name)} from {debug_quote(module.path)}\n"

	doc := cap_doc(d.doc, 500)
	if not doc.is_empty(): out = f"{out}{doc}\n"

	if d.members.is_empty():
		if not d.declaration.is_empty(): out = f"{out}{clip_lines(d.declaration.trim_end_chars("\n"), 12)}\n"
		return clip_text(out, 3500)

	out = f"{out}members ({d.members.length()}):\n"

	for i in 0..d.members.length():
		line := f"  {one_line(d.members[i].signature, 150)}\n"

		if out.length() + line.length() > 3500 - 160:
			out = f"{out}  ... {d.members.length() - i} more; use `ms search_symbol {short_name(module.path)}.{bare(d.name)}.<member>`\n"
			break

		out = f"{out}{line}"

	return f"{out}Details: ms search_symbol {short_name(module.path)}.{bare(d.name)}.<member>\n"

fn member_page(module: Module, d: Declaration, name: String) String?:
	var out = ""
	var count = 0

	for member in d.members:
		if bare(member.name) != name: continue

		count += 1
		if count > 3: break

		out = f"{out}{d.name}.{member.name} ({module.path})\n{clip_lines(member.signature.trim_end_chars("\n"), 6)}\n"

		doc := cap_doc(member.doc, 800)
		if not doc.is_empty(): out = f"{out}{doc}\n"

	if count == 0: return none

	return clip_text(out, 3500)

// The path split at its first two dots; `@std/` and the first `.ms` are dropped.
fn split_path(text: String) List[String]:
	var path = text.trim()

	if rest := path.cut_prefix("@std/"):
		path = rest.clone()
		if parts := path.split_once(".ms"): path = f"{parts.before}{parts.after}"

	var out = List[String]()
	var remaining = path.clone()

	while out.length() < 2:
		if parts := remaining.split_once("."):
			out.append(parts.before.clone())
			remaining = parts.after.clone()
		else: break

	out.append(remaining)
	return out

fn find_module(modules: List[Module], name: String) Module?:
	for module in modules:
		if short_name(module.path) == name or package_name(module.path) == name: return module.clone()
	return none

// Renders `ms search_symbol <path>`: a module, a declaration or one member; `none` when
// the path names nothing.
fn page(modules: List[Module], path: String) String?:
	parts := split_path(path)
	module := find_module(modules, parts[0])?
	if parts.length() == 1: return module_page(module)

	for d in module.declarations:
		if bare(d.name) != parts[1]: continue
		if parts.length() == 2: return declaration_page(module, d)

		return member_page(module, d, parts[2])

	return none

// ---- Ranking ----

type Entry:
	module: String
	name: String
	kind: String
	signature: String
	doc: String
	effects: List[String]
	words: List[String]
	doc_words: List[String]
	module_words: List[String]

type Match:
	module: String
	name: String
	kind: String
	signature: String
	doc: String
	effects: List[String]
	path: String
	score: Int

// Lowercased words of `text`, splitting punctuation, underscores and camelCase.
fn split_words(text: String) List[String]:
	var words = List[String]()
	var current = ""
	var previous_lower = false

	for ch in text.chars():
		scalar := ch.scalar_at(0)

		if is_uppercase(scalar) and previous_lower:
			if not current.is_empty():
				words.append(current.clone())
				current = ""

		if is_alphabetic(scalar) or is_numeric(scalar): current = current.concat(
			ch.lower()
		)
		else if not current.is_empty():
			words.append(current.clone())
			current = ""

		previous_lower = is_lowercase(scalar)

	if not current.is_empty(): words.append(current.clone())
	return words

// Keeps the leading paragraph and at most 3 lines.
fn first_block(text: String) String:
	paragraphs := text.split("\n\n")
	lines := paragraphs[0].trim_end_chars("\n").split("\n")
	if lines.length() <= 3: return lines.join("\n")

	return f"{lines[0]}\n{lines[1]}\n{lines[2]}\n    ..."

fn new_entry(
	path: String,
	short: String,
	name: String,
	kind: String,
	signature: String,
	doc: String,
) Entry:
	return Entry(
		path.clone(),
		name.clone(),
		kind.clone(),
		signature.clone(),
		doc.clone(),
		[],
		split_words(name),
		split_words(doc),
		split_words(short),
	)

fn standard_index(modules: List[Module]) List[Entry]:
	var out = List[Entry]()

	for module in modules:
		short := short_name(module.path)

		for d in module.declarations:
			trimmed := d.declaration.trim()
			signature := if trimmed.is_empty(): d.type.clone() else: trimmed
			var entry = new_entry(
				module.path,
				short,
				d.name,
				d.kind,
				first_block(signature),
				d.doc,
			)
			entry.effects = d.effects.clone()
			out.append(entry)
			for m in d.members:
				out.append(
					new_entry(
						module.path,
						short,
						f"{d.name}.{m.name}",
						m.kind,
						m.signature,
						m.doc,
					)
				)

	return out

fn stop_words() List[String]: [
	"a", "an", "the", "of", "to", "in", "for", "with", "by", "from", "and", "or", "how",
	"do"
]

// Drops filler so "sort by key" matches on "sort" and "key".
fn significant_words(query: String) List[String]:
	all := split_words(query)
	stops := stop_words()
	var kept = List[String]()
	for word in all:
		if not stops.contains(word) and word != "i": kept.append(word.clone())
	if kept.is_empty(): return all

	return kept

fn synonyms(token: String) List[String]:
	if token == "sort" or token == "order": return ["sorted"]
	if token == "uppercase": return ["upper"]
	if token == "lowercase": return ["lower"]
	if token == "size": return ["length", "count"]
	if token == "len": return ["length"]
	if token == "delete": return ["remove"]
	if token == "push": return ["append"]
	if token == "print": return ["write", "stdout"]
	if token == "stdin": return ["read_line"]
	if token == "concat": return ["join", "concat"]
	if token == "split": return ["split", "lines"]
	if token == "env": return ["environment"]
	if token == "random": return ["random"]

	return []

fn byte_list(text: String) List[Int]:
	bytes := text.as_bytes()
	var out = List[Int]()
	for i in 0..bytes.length(): out.append(bytes[i].to_int())
	return out

fn is_subsequence(small: String, large: String) Bool:
	wanted := byte_list(small)
	have := byte_list(large)
	var at = 0
	for i in 0..have.length():
		if at < wanted.length() and wanted[at] == have[i]: at += 1
	return at == wanted.length()

// The Damerau-Levenshtein distance with adjacent transpositions.
fn distance(a: List[Int], b: List[Int]) Int:
	cols := b.length() + 1
	var d = List[Int]()
	for _cell in 0..(a.length() + 1) * cols: d.append(0)
	for i in 0..a.length() + 1: d[i * cols] = i
	for j in 0..cols: d[j] = j

	for i in 1..a.length() + 1:
		for j in 1..cols:
			cost := if a[i - 1] != b[j - 1]: 1 else: 0
			var best = (d[(i - 1) * cols + j] + 1).min(d[i * cols + j - 1] + 1).min(
				d[(i - 1) * cols + j - 1] + cost
			)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]: best = best.min(
				d[(i - 2) * cols + j - 2] + 1
			)
			d[i * cols + j] = best

	return d[a.length() * cols + b.length()]

fn edit_distance(a: String, b: String) Int:
	if (a.length() - b.length()).abs() > 2: return 3
	return distance(a.scalar_values(), b.scalar_values())

fn allowed_typos(length: Int) Int: if length >= 7: 2 else: 1

// Scores one query word against a candidate word; `weight` scales the field.
fn score_word(token: String, word: String, weight: Int) Int:
	if token == word: return weight
	if word.starts_with(token) and token.length() >= 2: return weight * 7 / 10
	if token.length() >= 3 and word.contains(token): return weight / 2
	if weight < 50: return 0
	if (
		token.length() >= 3
		and token.as_bytes()[0] == word.as_bytes()[0]
		and is_subsequence(token, word)
	): return (weight * 3 / 10)
	if (
		token.length() >= 5
		and edit_distance(token, word) <= allowed_typos(token.length())
	): return (weight * 4 / 10)

	return 0

fn score_words(token: String, e: Entry) Int:
	var best = 0
	for word in e.words: best = best.max(score_word(token, word, 100))
	for word in e.module_words: best = best.max(score_word(token, word, 60))
	if token.length() >= 4:
		for word in e.doc_words: best = best.max(score_word(token, word, 12))
	return best

fn score_token(token: String, e: Entry) Int:
	var best = score_words(token, e)
	for alias in synonyms(token): best = best.max(score_words(alias, e) * 9 / 10)
	return best

// Rewards names whose words the query spells out, and penalizes extra words.
fn name_coverage(tokens: List[String], e: Entry) Int:
	var covered = 0
	for word in e.words:
		if tokens.contains(word): covered += 1
	return 15 * covered - 10 * (e.words.length() - covered)

fn compare_matches(a: Match, b: Match) Int:
	by_score := b.score.compare(a.score)
	if by_score != 0: return by_score

	a_other := if a.module != "prelude": 1 else: 0
	b_other := if b.module != "prelude": 1 else: 0
	by_module := a_other.compare(b_other)
	if by_module != 0: return by_module

	return f"{a.module}.{a.name}".compare(f"{b.module}.{b.name}")

STRONG_SCORE := 25

// Ranks standard declarations and members against a loose query: every query word must
// match somewhere, tolerating prefixes, subsequences and small typos.
fn search(entries: List[Entry], query: String, limit: Int) List[Match]:
	tokens := significant_words(query)
	if tokens.is_empty(): return []

	var matches = List[Match]()
	var best = 0

	for e in entries:
		var total = 0
		var matched = 0
		var strong = 0

		for token in tokens:
			score := score_token(token, e)

			if score > 0:
				total += score
				matched += 1
				if score >= STRONG_SCORE: strong += 1

		if (
			matched == 0
			or matched < best
			or (matched < tokens.length() and strong == 0)
		): continue

		if matched > best:
			best = matched
			matches = []

		total = total * 10 + name_coverage(tokens, e) - e.name.length().min(9)
		matches.append(
			Match(
				e.module.clone(),
				e.name.clone(),
				e.kind.clone(),
				e.signature.clone(),
				first_line(e.doc, 120),
				e.effects.clone(),
				std_path(e.module, e.name),
				total,
			)
		)

	matches.sort(compare_matches)

	var seen = Set[String]()
	var kept = List[Match]()

	for m in matches:
		key := f"{m.name.length()}:{m.name}{m.signature}"
		if seen.contains(key): continue

		seen.add(key)
		if kept.length() < limit: kept.append(m.clone())

	return kept

// ---- `name_rank` of the language server ----

fn fold(text: String) String: text.lower().replace("_", "").replace(".", "").replace(
	" ",
	"",
)

fn loose_rank(name: String, query: String) Int:
	if query.is_empty(): return -1
	if name == query: return 0
	if name.starts_with(query): return 1
	if name.contains(query): return 2

	n := byte_list(name)
	q := byte_list(query)
	if (
		q.length() >= 3
		and n.length() > 0
		and n[0] == q[0]
		and is_subsequence(query, name)
	): return 3
	if q.length() < 5: return -1
	if (n.length() - q.length()).abs() <= 2 and distance(n, q) <= 2: return 4
	if n.length() > q.length() and distance(n.slice(0, q.length()).get_or([]), q) <= 2: return 4

	return -1

fn name_rank(name: String, query: String) Int:
	folded := fold(query)
	var best = loose_rank(fold(name), folded)

	if parts := name.rsplit_once("."):
		own := loose_rank(fold(parts.after), folded)
		if own >= 0 and (best < 0 or own < best): best = own

	return best

// ---- The command ----

type Described:
	name: String
	kind: String
	definition: String
	symbol_type: String
	doc: String
	effects: String
	uses: List[String]
	std: Bool

type Ranked:
	rank: Int
	hit: Match

fn compare_ranked(a: Ranked, b: Ranked) Int: a.rank.compare(b.rank)

// Standard-library symbols follow project matches within the same result limit.
fn library_matches(
	entries: List[Entry],
	query: String,
	words: Int,
	project: Int,
	limit: Int,
) List[Described]:
	concept := search(entries, query, 50)
	var library = List[Ranked]()

	for m in concept:
		path := name_rank(m.path, query)
		own := name_rank(m.name, query)
		rank := if own >= 0 and (path < 0 or own < path): own else: path
		if rank >= 0: library.append(Ranked(rank, m.clone()))

	if project == 0 and (words > 1 or library.is_empty()):
		var seen = Set[String]()
		for ranked in library: seen.add(ranked.hit.path.clone())
		for m in concept:
			if not seen.contains(m.path): library.append(Ranked(5, m.clone()))

	library.sort(compare_ranked)

	var out = List[Described]()
	room := (limit - project).max(0)

	for ranked in library:
		if out.length() >= room: break

		m := ranked.hit
		effects := if m.kind == "fn" and not m.effects.is_empty(): f"effects: {m.effects.join(", ")}" else: ""
		out.append(
			Described(
				m.path.clone(),
				m.kind.clone(),
				f"std:{m.module}",
				squash(m.signature),
				m.doc.clone(),
				effects,
				[],
				true,
			)
		)

	return out

fn clip(text: String, limit: Int) String:
	if text.scalar_length() <= limit: return text.clone()
	return take_chars(text, limit - 1).concat("…")

fn render_text(
	query: String,
	described: List[Described],
	total: Int,
	project_count: Int,
) String:
	if described.is_empty(): return f"No project or standard-library symbol like {debug_quote(query)}. Try a shorter name.\n"

	var out = ""

	for m in described:
		out = f"{out}{m.name}  {m.kind}  {m.definition}\n"
		if not m.symbol_type.is_empty() and m.symbol_type != f"{m.name}: {m.name}": out = f"{out}  {clip(m.symbol_type, 200)}\n"
		if not m.doc.is_empty(): out = f"{out}  // {clip(m.doc, 160)}\n"
		if not m.effects.is_empty(): out = f"{out}  {m.effects}\n"

		if m.std:
			out = f"{out}  details: ms search_symbol {m.name}\n"
			continue

		shown := m.uses.length().min(5)
		out = f"{out}  used ({m.uses.length()})"

		if shown > 0:
			var names = List[String]()
			for i in 0..shown: names.append(m.uses[i].clone())
			out = f"{out}: {names.join(", ")}"

		if m.uses.length() > shown: out = f"{out}, ..."
		out = f"{out}\n"

	if total > project_count: out = f"{out}+{total - project_count} more project matches; use a longer name or --limit\n"

	if out.length() > 3500:
		out = out.slice(0, floor_boundary(out, 3500))
		out = f"{out}\n[... output cut; use a longer name ...]\n"

	return out

fn render_json(query: String, described: List[Described], total: Int) String:
	var matches = ""

	for i in 0..described.length():
		m := described[i]
		if i > 0: matches = f"{matches},"
		matches = f"{matches}\n    \{\n      \"name\": {json_string(m.name)},\n      \"kind\": {json_string(m.kind)},\n      \"definition\": {json_string(m.definition)}"
		if not m.symbol_type.is_empty(): matches = f"{matches},\n      \"type\": {json_string(m.symbol_type)}"
		if not m.doc.is_empty(): matches = f"{matches},\n      \"doc\": {json_string(m.doc)}"
		if not m.effects.is_empty(): matches = f"{matches},\n      \"effects\": {json_string(m.effects)}"
		if not m.uses.is_empty(): matches = f"{matches},\n      \"uses\": {string_array(m.uses, 3)}"

		origin := if m.std: "std" else: "project"
		matches = f"{matches},\n      \"origin\": \"{origin}\"\n    \}"

	listing := if described.is_empty(): "[]" else: f"[{matches}\n  ]"
	return f"\{\n  \"format\": 1,\n  \"query\": {json_string(query)},\n  \"project_total\": {total},\n  \"matches\": {listing}\n\}\n"

type Request:
	names: List[String]
	limit: Int
	json: Bool

fn parse_request(m: Matches) Request!:
	limit := m.int_or_none("limit").get_or(5)
	if limit < 1: return error(
		Error(
			"ms search_symbol: --limit needs a positive number, e.g. ms search_symbol Config --limit 3"
		)
	)

	return ok(Request(m.list("query"), limit.min(10), m.bool("json")))

fn blank(names: List[String]) Bool:
	for name in names:
		if not name.trim().is_empty(): return false
	return true

// The whole output of `ms search_symbol` for `request` with no project declarations.
fn run(modules: List[Module], request: Request) String:
	sorted := sorted_modules(modules)
	if blank(request.names): return index(sorted)

	query := request.names.join(" ")
	entries := standard_index(modules)
	if request.names.length() == 1 and not request.json:
		if text := page(sorted, query): return text

	described := library_matches(
		entries,
		query,
		request.names.length(),
		0,
		request.limit,
	)
	if request.json: return render_json(query, described, 0)

	return render_text(query, described, 0, 0)

// ms: allow_effect std.console.write
fn show(m: Matches) Void!:
	model := parse[Model](ms_tool_api_model())?
	request := parse_request(m)?
	var out = stdout()
	out.write(run(model.modules, request))?
	return ok()

fn main() Int:
	return run_tool(tree_tool("search_symbol", []), show)
