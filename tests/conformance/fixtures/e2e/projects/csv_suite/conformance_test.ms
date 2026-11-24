import (
	parse from "@std/data/csv.ms",
	FileTree, walk from "@std/os/tree.ms",
	expect_equal from "@std/test/test.ms",

	records from "./json_side.ms",
	files from "@suite",
)

// csv-spectrum: each `<name>.csv` parses to the records in `<name>.json`, where the first
// CSV row names the fields. A case outside `expect-fail.txt` must match; a listed case
// must still fail, so the list only ever shrinks.

fn read(tree: FileTree, path: String) String:
	return tree.read(path, null).get_or("".to_bytes()).decode_utf8() or ""

// Whether the parser agrees with the suite on one case.
fn passes(tree: FileTree, name: String) Bool:
	rows := parse(read(tree, f"{name}.csv"))
	want := records(read(tree, f"{name}.json"))
	if rows.is_error() or want.is_error(): return false

	table := rows.get_or([])
	expected := want.get_or([])
	if table.length() == 0: return expected.length() == 0
	if table.length() - 1 != expected.length(): return false

	header := table[0]

	for i in 0..expected.length():
		record := expected[i]
		row := table[i + 1]
		if row.length() != header.length() or record.length() != header.length(): return false

		for j in 0..header.length():
			if record.get_or(header[j], "\u{0}") != row[j]: return false

	return true

test "csv-spectrum agrees with the parser except for the listed cases":
	tree := files()
	var cases: List[String] = []
	for entry in walk(tree).get_or([]):
		if entry.path.ends_with(".csv"):
			cases.append(entry.path.slice(0, entry.path.length() - 4))

	var failing: List[String] = []
	for name in cases:
		if not passes(tree, name): failing.append(name.clone())
	failing.sort()

	listed := read(tree, "expect-fail.txt")
	var expected: List[String] = []

	for line in listed.split("\n"):
		name := line.split(" ").get_or(0, "")
		if name != "" and not name.starts_with("#"): expected.append(name.clone())

	expected.sort()
	cases.length() | expect_equal(12)?
	failing | expect_equal(expected)?
