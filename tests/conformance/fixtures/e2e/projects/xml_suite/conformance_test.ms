import (
	parse from "@std/data/xml.ms",
	FileTree from "@std/os/tree.ms",
	expect_equal from "@std/test/test.ms",

	files from "@suite",
)

// A selection of the W3C XML conformance suite (xmlts 2013-09-23): `not-wf` documents
// must be rejected, `valid` and `invalid` ones (well-formed, whatever their DTD says)
// must parse. The cases need no external entities and use the XML 1.0 fifth-edition
// rules; `cases.txt` names them. A case outside `expect-fail.txt` must behave as its
// type says; a listed case must still fail, so the list only ever shrinks. A reason
// starting `by design:` is a permanent decision.

// Whether the parser agrees with the suite on one case.
fn passes(tree FileTree, kind String, path String) Bool {
	bytes := tree.read(path, null).get_or("".to_bytes())
	text := bytes.decode_utf8()

	// A String cannot hold input that is not UTF-8, so such a document cannot be
	// accepted.
	if text == null { return kind == "not-wf" }

	parsed := parse(text)
	if kind == "not-wf" { return parsed.is_error() }

	return parsed.is_ok()
}

fn read(tree FileTree, path String) String {
	return tree.read(path, null).get_or("".to_bytes()).decode_utf8() or ""
}

test "the W3C XML suite agrees with the parser except for the listed cases" {
	tree := files()
	var cases = 0
	var failing List[String] = []

	for line in read(tree, "cases.txt").split("\n") {
		parts := line.split(" ")
		if parts.length() != 2 or line.starts_with("#") { continue }

		cases += 1
		if not passes(tree, parts[0], parts[1]) {
			failing.append(parts[1].clone())
		}
	}

	failing.sort()

	var expected List[String] = []
	var by_design = 0

	for line in read(tree, "expect-fail.txt").split("\n") {
		name := line.split(" ").get_or(0, "")
		if name != "" and not name.starts_with("#") {
			expected.append(name.clone())
		}
		if line.contains(" by design:") { by_design += 1 }
	}

	expected.sort()
	print(
		f"{cases} cases, {expected.length()} not passing, {by_design} unsupported by design"
	)
	cases | expect_equal(1216)?
	failing | expect_equal(expected)?
}
