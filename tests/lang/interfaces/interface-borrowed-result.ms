// conform: tags=interfaces,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

interface Label {
	fn text() String
	fn tags() List[String]
	fn nick() String?
	fn checked() String!
}

type Pet {
	name String
	labels List[String]
	alias String?
}

fn Pet.text() String {
	return self.name.clone()
}

fn Pet.tags() List[String] {
	return self.labels.clone()
}

fn Pet.nick() String? {
	return self.alias.clone()
}

fn Pet.checked() String! {
	return ok(self.name.clone())
}

fn describe(label Label) String {
	return label.text() + "/" + label.tags().length().to_string()
}

test "an interface operation returns the clone its method writes" {
	pet := Pet("rex", ["a", "b"], "r")
	view Label := pet
	expect_equal(view.text(), "rex")?
	expect_equal(view.tags(), ["a", "b"])?
	expect_equal(view.nick(), "r")?
	expect_equal(view.checked()?, "rex")?
	expect_equal(describe(pet), "rex/2")?
	expect_equal(pet.name, "rex")?
}

test "a result of an operation outlives the value it was read from" {
	var out List[String] = []

	for i in 0..3 {
		pet := Pet(f"p{i}", [], null)
		view Label := pet
		out.append(view.text())
	}

	expect_equal(out, ["p0", "p1", "p2"])?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
