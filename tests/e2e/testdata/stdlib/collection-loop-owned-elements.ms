import expect_equal from "@std/test/test.ms"

// These methods return owned lists. Moving an element must use that list, rather
// than the in-place map walk used when a loop only reads its element.
fn collect_values(source: Map[String, String]) List[String]:
    var out = List[String]()
    for value in source.values():
        out.append(value)
    return out

fn collect_entries(
    source: Map[String, List[String]]
) List[MapEntry[String, List[String]]]:
    var out = List[MapEntry[String, List[String]]]()
    for entry in source.entries():
        out.append(entry)
    return out

fn capture_keys(source: Map[String, Int]) List[fn() String]:
    var out = List[fn() String]()
    for key in source.keys():
        out.append(fn: key.clone())
    return out

test "map values move from their owned traversal result":
    let source = {"a": "alpha", "b": "beta", "c": "gamma"}
    try expect_equal(collect_values(source), ["alpha", "beta", "gamma"])
    try expect_equal(source.get("b").get(), "beta")

test "map entries retain independent nested values after a move":
    let source = {"a": ["alpha"], "b": ["beta"]}
    var entries = collect_entries(source)
    entries[0].value.append("changed")
    try expect_equal(entries[0].value, ["alpha", "changed"])
    try expect_equal(source.get("a").get(), ["alpha"])
    try expect_equal(entries[1].value, ["beta"])

test "map keys can move into escaping closures":
    let source = {"a": 1, "b": 2, "c": 3}
    let keys = capture_keys(source)
    try expect_equal(keys[0](), "a")
    try expect_equal(keys[1](), "b")
    try expect_equal(keys[2](), "c")
    try expect_equal(source.length(), 3)

test "set values move from their owned traversal result":
    let source = Set(["alpha", "beta", "gamma"])
    var out = List[String]()
    for value in source.values():
        out.append(value)
    try expect_equal(out, ["alpha", "beta", "gamma"])
    try expect_equal(source.length(), 3)
