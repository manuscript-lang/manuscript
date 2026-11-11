import expect_equal from "@std/test/test.ms"

// These methods return owned lists. Moving an element must use that list, rather
// than the in-place map walk used when a loop only reads its element.
fn collect_values(source: Map[String, String]) List[String]:
	var out = List[String]()
	out.extend(source.values())
	return out

fn collect_entries(
	source: Map[String, List[String]]
) List[MapEntry[String, List[String]]]:
	var out = List[MapEntry[String, List[String]]]()
	out.extend(source.entries())
	return out

fn capture_keys(source: Map[String, Int]) List[fn() String]:
	var out = List[fn() String]()
	for key in source.keys():
		out.append(fn: key.clone())
	return out

test "map values move from their owned traversal result":
	source := {"a": "alpha", "b": "beta", "c": "gamma"}
	expect_equal(collect_values(source), ["alpha", "beta", "gamma"])?
	expect_equal(source.get("b").get(), "beta")?

test "map entries retain independent nested values after a move":
	source := {"a": ["alpha"], "b": ["beta"]}
	var entries = collect_entries(source)
	entries[0].value.append("changed")
	expect_equal(entries[0].value, ["alpha", "changed"])?
	expect_equal(source.get("a").get(), ["alpha"])?
	expect_equal(entries[1].value, ["beta"])?

test "map keys can move into escaping closures":
	source := {"a": 1, "b": 2, "c": 3}
	keys := capture_keys(source)
	expect_equal(keys[0](), "a")?
	expect_equal(keys[1](), "b")?
	expect_equal(keys[2](), "c")?
	expect_equal(source.length(), 3)?

test "set values move from their owned traversal result":
	source := Set(["alpha", "beta", "gamma"])
	var out = List[String]()
	out.extend(source.values())
	expect_equal(out, ["alpha", "beta", "gamma"])?
	expect_equal(source.length(), 3)?
