// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn replace(var values Map[Int, Int]) Int:
	values.add(1, 9)
	return 0

test "a default that changes the map does not run when the key is present":
	var values = {1: 7}
	selected := values.get(1) or replace(values)
	expect_equal(selected, 7)?
	expect_equal(values.get(1) or 0, 7)?

test "a missing key still takes the default":
	var values = {1: 7}
	expect_equal(values.get(2) or replace(values), 0)?
