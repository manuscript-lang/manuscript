// conform: tags=testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Box {
	items List[String]
	label String
}

fn var Box.replace_items(next List[String]) List[String] {
	old := self.items
	self.items = next
	return old
}

test "a field bound and then assigned leaves the record with the new value" {
	var box = Box(["a", "b"], "x")
	old := box.replace_items(["c"])
	expect_equal(old, ["a", "b"])?
	expect_equal(box.items, ["c"])?
	expect_equal(box.label, "x")?
}
