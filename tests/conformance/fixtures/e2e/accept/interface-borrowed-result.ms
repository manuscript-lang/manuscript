// conform: tags=interfaces,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

interface Label:
	fn text() String
	fn tags() List[String]
	fn nick() String?
	fn checked() String!

type Pet:
	name: String
	labels: List[String]
	alias: String?

fn Pet.text() String:
	return self.name

fn Pet.tags() List[String]:
	return self.labels

fn Pet.nick() String?:
	return self.alias

fn Pet.checked() String!:
	return ok(self.name)

fn describe(label: Label) String:
	return label.text() + "/" + label.tags().length().to_string()

test "an interface operation returns a copy of a field the method borrows":
	pet := Pet("rex", ["a", "b"], "r")
	view: Label := pet
	expect_equal(view.text(), "rex")?
	expect_equal(view.tags(), ["a", "b"])?
	expect_equal(view.nick(), "r")?
	expect_equal(view.checked()?, "rex")?
	expect_equal(describe(pet), "rex/2")?
	expect_equal(pet.name, "rex")?

test "a result of an operation outlives the value it was read from":
	var out: List[String] = []

	for i in 0..3:
		pet := Pet("p{i}", [], none)
		view: Label := pet
		out.append(view.text())

	expect_equal(out, ["p0", "p1", "p2"])?
