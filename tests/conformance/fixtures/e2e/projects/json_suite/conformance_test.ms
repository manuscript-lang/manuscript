import (
	JsonValue, parse from "@std/data/json.ms",
	FileTree, walk from "@std/os/tree.ms",
	expect_equal from "@std/test/test.ms",

	files from "@suite",
)

// JSONTestSuite (nst/JSONTestSuite, `test_parsing`): `y_` files must parse and `n_`
// files must be rejected. The `i_` files are implementation-defined and not run. A case
// outside
// `expect-fail.txt` must behave as its prefix says; a listed case must still fail, so the
// list only ever shrinks.

// Whether the parser agrees with the suite on one case file.
fn passes(tree: FileTree, name: String) Bool:
	bytes := tree.read(name, null).get_or("".to_bytes())
	text := bytes.decode_utf8()

	// A String cannot hold invalid UTF-8, so such a file cannot be accepted.
	if text == null: return name.starts_with("n_")

	parsed := parse[JsonValue](text)
	if name.starts_with("n_"): return parsed.is_error()

	return parsed.is_ok()

test "JSONTestSuite agrees with the parser except for the listed cases":
	tree := files()
	var cases: List[String] = []
	for entry in walk(tree).get_or([]):
		if entry.path.ends_with(".json"): cases.append(entry.path.clone())

	var failing: List[String] = []
	for name in cases:
		if not passes(tree, name): failing.append(name.clone())
	failing.sort()

	listed := (
		tree.read("expect-fail.txt", null).get_or("".to_bytes()).decode_utf8()
		or ""
	)
	var expected: List[String] = []

	for line in listed.split("\n"):
		name := line.split(" ").get_or(0, "")
		if name != "" and not name.starts_with("#"): expected.append(name.clone())

	expected.sort()
	cases.length() | expect_equal(283)?
	failing | expect_equal(expected)?
