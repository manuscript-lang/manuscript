// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Titled:
	title: String

type Holder:
	text: String

fn quoted(t: Titled) String:
	return "{t.title}"

test "a lone interpolation of a borrowed string is a new string wherever it is owned":
	t := Titled("a")
	var xs = List[String]()
	xs.append("{t.title}")

	h := Holder("{t.title}")
	f := fn: "{t.title}"
	expect_equal(quoted(t), "a")?
	expect_equal(xs, ["a"])?
	expect_equal(h.text, "a")?
	expect_equal(f(), "a")?
