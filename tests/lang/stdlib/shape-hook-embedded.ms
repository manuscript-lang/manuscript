// conform: tags=testing,tier-stdlib
// conform: phase=test
import stringify, JsonValue from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

// A record with its own text form, stored inside an optional or a Result, has its leaves where the host puts them. The
// hook must still read the value in its own layout.
type Tag {
	on Bool
	n Int
	off Bool
}

fn Tag.to_string() String {
	return f"Tag<{self.on},{self.n},{self.off}>"
}

fn made() Tag! {
	return ok(Tag(on: true, n: 77, off: false))
}

fn maybe() Tag? {
	return Tag(on: false, n: 5, off: true)
}

test "a text form inside a Result" {
	expect_equal(f"{made()}", "ok(Tag<true,77,false>)")?
}

test "a text form inside an optional" {
	expect_equal(f"{maybe()}", "some(Tag<false,5,true>)")?
}

type Wide {
	on Bool
	n Int
	off Bool
}

fn Wide.to_json() JsonValue {
	return JsonValue.StringValue(f"wide:{self.on},{self.n},{self.off}")
}

fn wide() Wide! {
	return ok(Wide(on: true, n: 41, off: true))
}

test "a JSON form inside a Result" {
	expect_equal(stringify(wide())?, "{\"ok\":{\"value\":\"wide:true,41,true\"}}")?
}
