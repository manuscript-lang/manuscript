// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn and_then[T, U](value: T?, transform: fn(T) U?) U?:
	if value == null: return null
	return transform(value)

fn doc() JsonValue:
	text := "{\"user\":{\"name\":\"ada\",\"age\":36,\"score\":1.5,\"big\":1e3,\"admin\":true,\"tags\":[\"a\",\"b\",\"c\"]},\"none\":null}"
	return parse(text).get()

fn user_field(d: JsonValue, key: String) JsonValue?:
	user := d.get("user")

	if user != null:
		field := user.get(key)
		if field != null: return field.clone()

	return null

fn string_of(value: JsonValue) String?:
	text := value.as_string()
	if text != null: return text.clone()

	return null

fn has_map(value: JsonValue) Bool:
	return value.as_map() != null

fn tag(d: JsonValue, index: Int) String?:
	tags := d.get("user")

	if tags != null:
		list := tags.get("tags")

		if list != null:
			item := list.get_index(index)
			if item != null: return string_of(item)

	return null

test "JSON accessors read nested objects without copying subtrees":
	d := doc()
	expect_equal(user_field(d, "name"), JsonValue.StringValue("ada"))?
	expect_equal(and_then(user_field(d, "name"), fn n: string_of(n)), "ada")?
	expect_equal(and_then(user_field(d, "age"), fn n: n.as_int()), 36)?
	expect_equal(and_then(user_field(d, "admin"), fn n: n.as_bool()), true)?
	expect_equal(and_then(user_field(d, "score"), fn n: n.as_float()), 1.5)?
	expect_equal(and_then(user_field(d, "age"), fn n: n.as_float()), 36.0)?
	expect_true(user_field(d, "missing") == null)?

test "JSON at indexes arrays from either end":
	d := doc()
	expect_equal(tag(d, 0), "a")?
	expect_equal(tag(d, -1), "c")?
	expect_equal(tag(d, -3), "a")?
	expect_true(tag(d, 3) == null)?
	expect_true(tag(d, -4) == null)?

test "JSON borrowed list and map views match the tree":
	d := doc()
	user := d.get("user")

	if user != null:
		tags := user.get("tags")

		if tags != null:
			list := tags.as_list()
			if list != null:
				expect_equal(list.length(), 3)?

		members := user.as_map()
		if members != null:
			expect_equal(members.length(), 6)?

	expect_true(d.as_map() != null)?

test "JSON accessors return none for the wrong type":
	d := doc()
	expect_true(d.get("missing") == null)?
	expect_true(d.get_index(0) == null)?
	expect_true(d.as_string() == null)?
	expect_true(d.as_list() == null)?
	expect_true(d.as_bool() == null)?
	expect_true(and_then(user_field(d, "name"), fn n: n.as_int()) == null)?
	expect_true(and_then(user_field(d, "age"), fn n: string_of(n)) == null)?
	expect_true(and_then(user_field(d, "age"), fn n: n.as_bool()) == null)?
	expect_true(and_then(user_field(d, "name"), fn n: n.as_float()) == null)?

	tags := user_field(d, "tags")
	expect_true(tags != null and not has_map(tags))?

test "JSON as_int rejects fractions exponents and overflow":
	d := doc()
	expect_true(and_then(user_field(d, "score"), fn n: n.as_int()) == null)?
	expect_true(and_then(user_field(d, "big"), fn n: n.as_int()) == null)?
	expect_equal(and_then(user_field(d, "big"), fn n: n.as_float()), 1000.0)?

	huge := parse("99999999999999999999")?
	expect_true(huge.as_int() == null)?

	neg := parse("-7")?
	expect_equal(neg.as_int(), -7)?

test "JSON is_null distinguishes null from absent and other values":
	d := doc()
	value := d.get("none")
	if value != null:
		expect_true(value.is_null())?

	user := d.get("user")
	if user != null:
		expect_false(user.is_null())?
	expect_true(d.get("missing") == null)?

// `get_in` returns a clone of the member it reaches.
fn user_name(d: JsonValue) String?:
	name := d.get_in(["user", "name"])
	if name != null: return name.as_string()

	return null

test "JSON get_in reads a chain of members in place":
	d := doc()
	expect_equal(user_name(d), "ada")?
	expect_equal(and_then(d.get_in(["user", "age"]).clone(), fn n: n.as_int()), 36)?

	tags := d.get_in(["user", "tags"])

	if tags != null:
		last := tags.get_index(-1)
		if last != null: expect_equal(string_of(last), "c")?

	expect_true(d.get_in(["user", "missing"]) == null)?
	expect_true(d.get_in(["user", "name", "first"]) == null)?
	expect_true(d.get_in([]) == null)?
