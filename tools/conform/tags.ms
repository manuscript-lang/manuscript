// The tag vocabulary of the corpus and the rules that derive tags from source text,
// shared by `lint`, `retag` and `harvest`.

// Feature-area tags. Stdlib modules are `stdlib-<module>`; anything else is rejected by
// `lint`.
TAGS: List[String] := [
	"lexer", "layout", "parser", "formatter", "types", "generics", "interfaces",
	"closures", "match", "destructuring", "try-result", "optional", "scope-cleanup",
	"faults", "strings", "lists", "maps", "sets", "numbers", "decimal", "interpolation",
	"records", "alternatives", "control-flow", "functions", "modules", "projects",
	"diagnostics", "mutation", "json-protocol", "docs", "examples", "perf", "fuzz",
	"bench", "stdlib", "cli", "testing", "aliasing", "tier-core", "tier-stdlib",
	"tier-io", "cancellation", "defaults", "lowering", "ownership", "resources",
	"syntax", "text", "var-parameters"
]
// Projects that bind sockets, wait for signals or spawn processes; they are checked,
// not run.
HOSTILE_IMPORTS: List[String] := [
	"http", "net", "tls", "websocket", "sse", "fetch", "process", "terminal", "system",
	"random", "time"
]
// Modules that read or write the host; they put a fixture in the `io` tier.
IO_IMPORTS: List[String] := ["fs", "path", "log", "system"]

export fn tag_allowed(tag: String) Bool:
	if TAGS.contains(tag): return true
	return tag.starts_with("stdlib-") and tag.length() > "stdlib-".length()

export fn hostile(text: String) Bool:
	for name in imports_of(text):
		if HOSTILE_IMPORTS.contains(name): return true
	return false

// The names of the `@std/...` modules `text` imports, sorted and without repeats.
export fn imports_of(text: String) List[String]:
	var found = List[String]()
	var rest = text.clone()

	while true:
		at := rest.index_of("\"@std/").get_or(-1)
		if at < 0: break

		rest = rest.slice(at + 6, rest.length()).clone()

		var end = 0

		while end < rest.length():
			c := rest.slice(end, end + 1)
			if c == "." or c == "\"": break

			end += 1

		path := rest.slice(0, end)
		var name = path.clone()
		slash := path.last_index_of("/").get_or(-1)
		if slash >= 0: name = path.slice(slash + 1, path.length()).clone()

		var valid = name != ""

		for index in 0..name.length():
			c := name.slice(index, index + 1)
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")): valid = false

		if valid and not found.contains(name): found.append(name.clone())

	found.sort()
	return found

// The milestone tier of a program: stdout and the test harness are part of the core
// language experience, so `io` and `testing` do not raise it.
export fn tier_of(imports: List[String]) String:
	var others = List[String]()
	for name in imports:
		if name != "io" and name != "testing": others.append(name.clone())
	if others.is_empty(): return "tier-core"

	for name in others:
		if IO_IMPORTS.contains(name) or HOSTILE_IMPORTS.contains(name): return "tier-io"
	return "tier-stdlib"

// Programs whose answer can depend on assignment sharing: explicit `.clone()`, or a
// binding of one name to another next to an in-place mutation. Over-tagging is safe.
export fn aliasing_dependent(text: String) Bool:
	if text.contains(".clone()"): return true

	var mutates = false
	for call in [
		".add(", ".append(", ".push(", ".insert(", ".remove(", ".set(", ".clear("
	]:
		if text.contains(call): mutates = true
	if text.contains("[0] = ") or text.contains("] = "): mutates = true

	for line in text.split("\n"):
		trimmed := line.trim_start()
		at := trimmed.index_of(" = ").get_or(-1)
		if at < 0: continue

		left := trimmed.slice(0, at)
		if left.contains(".") and not left.contains(" "): mutates = true

	if not mutates: return false

	for line in text.split("\n"):
		trimmed := line.trim()
		var right = ""

		if trimmed.starts_with("var "):
			at := trimmed.index_of(" = ").get_or(-1)
			if at < 0: continue

			right = trimmed.slice(at + 3, trimmed.length()).trim().clone()
		else:
			at := trimmed.index_of(" := ").get_or(-1)
			if at < 0: continue

			right = trimmed.slice(at + 4, trimmed.length()).trim().clone()

		if right == "": continue

		var plain = true

		for index in 0..right.length():
			c := right.slice(index, index + 1)
			word := (
				(c >= "a" and c <= "z")
				or (c >= "A" and c <= "Z")
				or (c >= "0" and c <= "9")
				or c == "_"
				or c == "."
			)
			if not word: plain = false

		if plain: return true

	return false

// Feature tags from the source text (conservative keyword rules).
export fn tags_for(text: String, phase: String) List[String]:
	var tags = List[String]()
	rules: List[List[String]] := [
		["match ", "match"],
		["try ", "try-result"],
		["Result[", "try-result"],
		["?", "optional"],
		["some(", "optional"],
		["interface ", "interfaces"],
		["impl ", "interfaces"],
		["case ", "alternatives"],
		["fn(", "closures"],
		[" -> ", "closures"],
		["List[", "lists"],
		["Map[", "maps"],
		["Set[", "sets"],
		["Decimal", "decimal"],
		["Float", "numbers"],
		["panic", "faults"],
		[".get(", "faults"],
		["for ", "control-flow"],
		["while ", "control-flow"],
		["if ", "control-flow"],
		["type ", "records"],
		["var ", "mutation"],
		["test \"", "testing"],
		["import ", "modules"],
	]
	for rule in rules:
		if text.contains(rule[0]): tags.append(rule[1].clone())
	if text.contains("fn ") and text.contains("[T"): tags.append("generics")
	if text.contains("] :=") or text.contains("} :="): tags.append("destructuring")

	for line in text.split("\n"):
		quote := line.index_of("\"").get_or(-1)

		if quote >= 0 and line.slice(quote, line.length()).contains("{"):
			tags.append("interpolation")
			break

	if text.contains("String"): tags.append("strings")

	imports := imports_of(text)
	for name in imports: tags.append(f"stdlib-{name}")
	tags.append(tier_of(imports))
	if aliasing_dependent(text): tags.append("aliasing")

	if phase == "parse": tags.append("parser")
	else if phase == "check": tags.append("diagnostics")
	else if phase == "test": tags.append("testing")

	var only_tiers = true
	for tag in tags:
		if not tag.starts_with("tier-"): only_tiers = false
	if only_tiers: tags.append("functions")
	return sorted_unique(tags)

export fn sorted_unique(items: List[String]) List[String]:
	var out = List[String]()
	var ordered = items.clone()
	ordered.sort()
	for item in ordered:
		if out.is_empty() or out[out.length() - 1] != item: out.append(item.clone())
	return out

// A lowercase ASCII slug of `text`, at most 60 characters.
export fn slugify(text: String) String:
	var out = ""
	var dash = true

	for index in 0..text.length():
		c := text.slice(index, index + 1).lower()
		alnum := (c >= "a" and c <= "z") or (c >= "0" and c <= "9")

		if alnum:
			out += c
			dash = false
		else if not dash:
			out += "-"
			dash = true

	while out.ends_with("-"): out = out.slice(0, out.length() - 1).clone()
	if out.length() > 60: out = out.slice(0, 60).clone()
	return out
