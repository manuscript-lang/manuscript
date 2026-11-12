// conform: tags=interfaces,records,strings,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

interface Named:
	fn label() String

type Tag:
	name: String
	n: Int

fn Tag.label() String:
	return "{self.name}-{self.n}"

fn describe(x: Named) String:
	return x.label()

fn twice(x: Named) String:
	return "{x.label()}{x.label()}"

fn keep(x: Named) Named:
	return x

test "a borrowed value passed as an interface is read in place":
	tag := Tag("a-name-longer-than-twenty-two-bytes", 7)
	var out = ""
	for i in 0..3:
		out = "{out}{describe(tag)}|"
	expect_equal(out, "a-name-longer-than-twenty-two-bytes-7|a-name-longer-than-twenty-two-bytes-7|a-name-longer-than-twenty-two-bytes-7|")?
	expect_equal(twice(tag).length(), 74)?

test "an interface that outlives the call keeps its own copy":
	tag := Tag("short", 1)
	kept := keep(tag)
	expect_equal(kept.label(), "short-1")?
	items: List[Named] := [tag, Tag("b", 2)]
	expect_equal(items.map(fn n: n.label()), ["short-1", "b-2"])?
