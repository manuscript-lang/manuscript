import (
	YamlValue, parse_all from "@std/data/yaml.ms",
	parse_int from "@std/math/math.ms",
	FileTree, walk from "@std/os/tree.ms",
	expect_equal from "@std/test/test.ms",

	canon_json_stream from "./json_side.ms",
	files from "@suite",
)

// The official yaml-test-suite (data release 2022-01-17), one directory per case with
// `in.yaml`, an `error` marker for invalid input, and `in.json` for valid input. A case
// outside `expect-fail.txt` must behave as the suite says; a listed case must still
// fail. The list names what is not supported yet and only ever shrinks.

fn canon(value YamlValue) String {
	match value {
		Null => return "n"
		BoolValue(flag) => return if flag { "t" } else { "f" }
		NumberValue(text) => return f"N{number(text)}"
		StringValue(text) => return f"s{text.length()}:{text}"
		ArrayValue(items) => {
			var parts List[String] = []
			for item in items {
				parts.append(canon(item))
			}
			return f"[{parts.join(",")}]"
		}
		ObjectValue(members) => {
			var parts List[String] = []
			for entry in members.entries() {
				parts.append(f"{entry.key.length()}:{entry.key}={canon(entry.value)}")
			}
			parts.sort()
			return f"\{{parts.join(",")}\}"
		}
	}
}

// The value of a YAML core-schema number spelling.
fn number(text String) Float {
	f := text.parse_float()
	if f != null { return f }

	digits := text.slice(2, text.length())
	if text.starts_with("0x") {
		return parse_int(digits, 16).get_or(0).to_float()
	}
	if text.starts_with("0o") {
		return parse_int(digits, 8).get_or(0).to_float()
	}

	return 0.0
}

fn exists(tree FileTree, path String) Bool {
	return tree.read(path, null).is_ok()
}

// Whether the parser agrees with the suite on one case directory.
fn passes(tree FileTree, id String) Bool {
	text := tree.read(f"{id}/in.yaml", null).get_or("".to_bytes()).decode_utf8() or ""
	parsed := parse_all(text)
	if exists(tree, f"{id}/error") { return parsed.is_error() }
	if parsed.is_error() { return false }
	if not exists(tree, f"{id}/in.json") { return true }

	json := tree.read(f"{id}/in.json", null).get_or("".to_bytes()).decode_utf8() or ""
	want := canon_json_stream(json)
	if want.is_error() { return false }

	var got List[String] = []
	for document in parsed.get_or([]) {
		got.append(canon(document))
	}
	return got == want.get_or([])
}

test "the official YAML suite agrees with the parser except for the listed cases" {
	tree := files()
	var cases List[String] = []
	for entry in walk(tree).get_or([]) {
		if entry.path.ends_with("/in.yaml") {
			cases.append(entry.path.slice(0, entry.path.length() - 8))
		}
	}

	var failing List[String] = []
	for id in cases {
		if not passes(tree, id) { failing.append(id.clone()) }
	}
	failing.sort()

	listed := (
		tree.read("expect-fail.txt", null).get_or("".to_bytes()).decode_utf8()
		or ""
	)
	var expected List[String] = []

	for line in listed.split("\n") {
		name := line.split(" ").collect().get_or(0, "")
		if name != "" and not name.starts_with("#") {
			expected.append(name.clone())
		}
	}

	var by_design = 0
	for line in listed.split("\n") {
		if line.contains(" by design:") { by_design += 1 }
	}
	expected.sort()
	print(
		f"{cases.length()} cases, {expected.length()} not passing, {by_design} unsupported by design"
	)
	cases.length() | expect_equal(cases.length())?
	failing | expect_equal(expected)?
}
