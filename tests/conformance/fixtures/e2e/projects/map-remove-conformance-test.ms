// conform: tags=diagnostics,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/map_remove/conformance_test.ms
import (
	expect_false, expect_true from "@std/test/test.ms",

	id_bound, id_direct, id_generic, id_map from "./by_id.ms",
	label_bound, label_direct, label_generic, label_map from "./by_label.ms",
	Key from "./key.ms",
)

test "Map removal keeps direct bound generic and defining-module key scopes":
	var first = id_map()
	id_direct(var first, Key(1, "different"))
	id_bound(var first, Key(2, "different"))
	id_generic(var first, Key(3, "different"))
	(first.is_empty()) | expect_true?

	var second = label_map()
	label_direct(var second, Key(99, "one"))
	label_bound(var second, Key(99, "two"))
	label_generic(var second, Key(99, "three"))
	(second.is_empty()) | expect_true?

	var returned_values = id_map()
	remove := returned_values.remove
	remove(Key(1, "different"))
	expect_false((returned_values.length() != 2 or returned_values.keys()[0].id != 2))?
