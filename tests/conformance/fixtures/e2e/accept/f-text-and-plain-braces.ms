// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "plain text keeps braces as written" {
	expect_equal("{name} { }".length(), 10)?
	expect_equal("{\"a\": 1}".length(), 8)?
	expect_equal(r"{name}", "{name}")?
}

test "f text interpolates and escapes braces" {
	name := "Sam"
	expect_equal(f"{name} \{name\}", "Sam {name}")?
	expect_equal(f"{name.length() + 1}", "4")?
	expect_equal(f"[{f"<{name}>"} {"{name}"}]", "[<Sam> {name}]")?
}

test "multi-line text interpolates only as f text" {
	name := "Sam"
	greeting := f"""
	  hi {name}
	  """
	expect_equal(greeting, "hi Sam")?

	literal := """
	  hi {name}
	  """
	expect_equal(literal, "hi {name}")?
}
