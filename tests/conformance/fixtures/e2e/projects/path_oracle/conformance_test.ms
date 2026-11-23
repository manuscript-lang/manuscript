import (
	hex_decode, hex_encode from "@std/data/encoding.ms",
	PathOperations, PathParts, posix, win32 from "@std/os/path.ms",
	fail from "@std/test/test.ms",

	files from "@oracle",
)

// Replays data/path.tsv, the corpus recorded from the original path implementation (the
// Go oracle, then the Rust natives): one case per line as
// `operation<TAB>windows<TAB>inputs...<TAB>=><TAB>expected`. A text is `x` followed by
// the hex of its UTF-8 bytes; a list is `[x61,x62]`; path parts are five texts
// separated by spaces.

fn text(token: String) String:
	digits := token.view(1, token.length())
	bytes := hex_decode(digits, none) | .get_or("".to_bytes())
	return bytes.decode_utf8().get_or("")

fn hex(value: String) String:
	return f"x{hex_encode(value.to_bytes())}"

fn list_of(token: String) List[String]:
	inner := token.slice(1, token.length() - 1)
	if inner.is_empty(): return []

	return inner.split(",").map(fn item: text(item))

fn parts_of(token: String) PathParts:
	f := token.split(" ").map(fn item: text(item))
	return PathParts(
		root: f[0].clone(),
		directory: f[1].clone(),
		base: f[2].clone(),
		extension: f[3].clone(),
		name: f[4].clone(),
	)

fn parts_text(parts: PathParts) String:
	return [parts.root.clone(), parts.directory.clone(), parts.base.clone(), parts.extension.clone(), parts.name.clone()].map(
		fn item: hex(item)
	).join(" ")

fn result(outcome: String!) String:
	if value := outcome: return f"ok {hex(value)}"
	return "err InvalidInput"

fn answer(rules: PathOperations, f: List[String]) String:
	op := f[0]
	if op == "basename": return hex(rules.basename(text(f[2])))
	if op == "basename_without": return hex(
		rules.basename_without(text(f[2]), text(f[3]))
	)
	if op == "dirname": return hex(rules.dirname(text(f[2])))
	if op == "extension": return hex(rules.extension(text(f[2])))
	if op == "is_absolute": return if rules.is_absolute(text(f[2])): "1" else: "0"
	if op == "normalize": return hex(rules.normalize(text(f[2])))
	if op == "namespaced": return hex(rules.to_namespaced_path(text(f[2])))
	if op == "parse": return parts_text(rules.parse(text(f[2])))
	if op == "format": return hex(rules.format(parts_of(f[2])))
	if op == "join": return hex(rules.join(list_of(f[2])))

	if op == "resolve":
		parts := if f[3] == "[]": List[String]() else: list_of(f[3])
		return result(rules.resolve(text(f[2]), parts))

	if op == "relative": return result(rules.relative(text(f[2]), text(f[3])))

	if op == "glob":
		if matched := rules.matches_glob(text(f[2]), text(f[3])):
			return f"ok {if matched: 1 else: 0}"
		return "err InvalidInput"

	return f"unknown case {op}"

test "path operations match the recorded corpus":
	data := (
		files().read("path.tsv", none)
		| .get_or("".to_bytes())
		| .decode_utf8()
		| .get_or("")
	)
	var checked = 0
	var failures = List[String]()

	for line in data.split("\n"):
		if line.is_empty() or line.starts_with("#"): continue

		f := line.split("\t")
		want := f[f.length() - 1]
		rules := if f[1] == "1": win32() else: posix()
		got := answer(rules, f)
		checked += 1
		if got != want and failures.length() < 10: failures.append(f"{line} -> {got}")

	if not failures.is_empty(): return fail(
		f"{failures.length()} mismatches, first:\n{failures.join("\n")}"
	)
	if checked < 9000: return fail(f"only {checked} cases")

	return ok()
