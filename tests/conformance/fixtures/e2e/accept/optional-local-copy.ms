// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn grown() Int:
	var o List[String]? = ["a"]
	l := o

	if l != null:
		var copy = l.clone()
		copy.append("q")
		return copy.length()

	return 0

test "an optional local is changed through an independent copy":
	expect_equal(grown(), 2)?
