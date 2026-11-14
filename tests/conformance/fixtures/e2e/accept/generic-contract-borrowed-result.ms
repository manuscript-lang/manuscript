// conform: tags=generics,interfaces,testing,tier-core
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

fn text_of[T: Label](item: T) String:
	return item.text()

fn first_text[T: Label](items: List[T]) String:
	return items[0].text()

fn tag_count[T: Label](item: T) Int:
	tags := item.tags()
	return tags.length()

fn nick_of[T: Label](item: T) String?:
	return item.nick()

fn checked_of[T: Label](item: T) String!:
	return item.checked()

test "a generic body copies what a bound operation borrows from its receiver":
	pet := Pet("rex", ["a", "b"], "r")
	expect_equal(text_of(pet), "rex")?
	expect_equal(first_text([pet.clone()]), "rex")?
	expect_equal(tag_count(pet), 2)?
	expect_equal(nick_of(pet), "r")?
	expect_equal(checked_of(pet)?, "rex")?
	expect_equal(pet.name, "rex")?

test "the copy outlives the value it came from":
	var out: List[String] = []

	for i in 0..3:
		pet := Pet("p{i}", [], none)
		out.append(text_of(pet))

	expect_equal(out, ["p0", "p1", "p2"])?
