// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `map.get(k).get(default)` copies the value out, so it can start a `var` and be changed
// without touching the map (only a lent slice keeps its borrow through `get(default)`).
fn lookup(table: Map[String, String], key: String) String:
	var found = table.get_or("default", "")
	own := table.get(key)
	if own != null: found = own.clone()
	found += "!"
	return found

test "a map value read with get(default) is an owned var":
	table := {"default": "d", "a": "x"}
	void expect_equal(lookup(table, "a"), "x!")?
	void expect_equal(lookup(table, "b"), "d!")?
	return expect_equal(table.get_or("default", ""), "d")
