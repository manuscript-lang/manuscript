import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn doc() JsonValue:
	text := "\{\"user\":\{\"name\":\"ada\",\"age\":36,\"score\":1.5,\"big\":1e3,\"admin\":true,\"tags\":[\"a\",\"b\",\"c\"]\},\"none\":null\}"
	return parse(text).get()

fn user_field(d: JsonValue, key: String) JsonValue?:
	if user := d.get("user"):
		if field := user.get(key): return field.clone()
	return none

fn string_of(value: JsonValue) String?:
	if text := value.as_string(): return text.clone()
	return none

fn has_map(value: JsonValue) Bool:
	return value.as_map().is_some()

fn tag(d: JsonValue, index: Int) String?:
	if tags := d.get("user"):
		if list := tags.get("tags"):
			if item := list.at(index): return string_of(item)
	return none

test "JSON accessors read nested objects without copying subtrees":
	d := doc()
	expect_equal(user_field(d, "name"), JsonValue.StringValue("ada"))?
	expect_equal(user_field(d, "name").and_then(fn n: string_of(n)), "ada")?
	expect_equal(user_field(d, "age").and_then(fn n: n.as_int()), 36)?
	expect_equal(user_field(d, "admin").and_then(fn n: n.as_bool()), true)?
	expect_equal(user_field(d, "score").and_then(fn n: n.as_float()), 1.5)?
	expect_equal(user_field(d, "age").and_then(fn n: n.as_float()), 36.0)?
	expect_true(user_field(d, "missing").is_none())?

test "JSON at indexes arrays from either end":
	d := doc()
	expect_equal(tag(d, 0), "a")?
	expect_equal(tag(d, -1), "c")?
	expect_equal(tag(d, -3), "a")?
	expect_true(tag(d, 3).is_none())?
	expect_true(tag(d, -4).is_none())?

test "JSON borrowed list and map views match the tree":
	d := doc()

	if user := d.get("user"):
		if tags := user.get("tags"):
			if list := tags.as_list():
				expect_equal(list.length(), 3)?
		if members := user.as_map():
			expect_equal(members.length(), 6)?

	expect_true(d.as_map().is_some())?

test "JSON accessors return none for the wrong type":
	d := doc()
	expect_true(d.get("missing").is_none())?
	expect_true(d.at(0).is_none())?
	expect_true(d.as_string().is_none())?
	expect_true(d.as_list().is_none())?
	expect_true(d.as_bool().is_none())?
	expect_true(user_field(d, "name").and_then(fn n: n.as_int()).is_none())?
	expect_true(user_field(d, "age").and_then(fn n: string_of(n)).is_none())?
	expect_true(user_field(d, "age").and_then(fn n: n.as_bool()).is_none())?
	expect_true(user_field(d, "name").and_then(fn n: n.as_float()).is_none())?
	expect_true(user_field(d, "tags").map(fn n: has_map(n)).get(true) == false)?

test "JSON as_int rejects fractions exponents and overflow":
	d := doc()
	expect_true(user_field(d, "score").and_then(fn n: n.as_int()).is_none())?
	expect_true(user_field(d, "big").and_then(fn n: n.as_int()).is_none())?
	expect_equal(user_field(d, "big").and_then(fn n: n.as_float()), 1000.0)?

	huge := parse("99999999999999999999")?
	expect_true(huge.as_int().is_none())?

	neg := parse("-7")?
	expect_equal(neg.as_int(), -7)?

test "JSON is_null distinguishes null from absent and other values":
	d := doc()
	if value := d.get("none"):
		expect_true(value.is_null())?
	if user := d.get("user"):
		expect_false(user.is_null())?
	expect_true(d.get("missing").is_none())?

// `get_in` returns a clone of the member it reaches.
fn user_name(d: JsonValue) String?:
	if name := d.get_in(["user", "name"]): return name.as_string()
	return none

test "JSON get_in reads a chain of members in place":
	d := doc()
	expect_equal(user_name(d), "ada")?
	expect_equal(d.get_in(["user", "age"]).and_then(fn n: n.as_int()), 36)?
	if tags := d.get_in(["user", "tags"]):
		expect_equal(tags.at(-1).and_then(fn t: string_of(t)), "c")?
	expect_true(d.get_in(["user", "missing"]).is_none())?
	expect_true(d.get_in(["user", "name", "first"]).is_none())?
	expect_true(d.get_in([]).is_none())?
