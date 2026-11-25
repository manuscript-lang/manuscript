// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",
)

type Repo {
	n Int = 1
}

// A `to_json` that is not `fn to_json() JsonValue` is an ordinary method, not the JSON
// encoder, so `stringify(self)` inside it encodes the fields instead of recursing.
fn Repo.to_json() String! {
	return stringify(self)
}

test "a to_json with another shape does not encode the type" {
	repo := Repo()
	text := repo.to_json()?
	expect_equal(text, "{\"n\":1}")?
}
