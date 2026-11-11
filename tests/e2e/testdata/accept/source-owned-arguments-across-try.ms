import expect_equal from "@std/test/test.ms"

fn successful_value(value: Int) Int!:
	return ok(value)

fn consume(key: String, value: Int) Int:
	keys := [key]
	return keys.length() + value

type Box:
	text: String

impl Box:
	fn consume(value: Int) Int:
		boxes := [self]
		return boxes.length() + value

test "source consuming argument remains owned after later try":
	key := "long-dynamic-map-key-{1}"
	expect_equal(consume(key, successful_value(7)?), 8)?

test "source consuming receiver remains owned after later try":
	box := Box("long-dynamic-map-key-{1}")
	expect_equal(box.consume(successful_value(7)?), 8)?
