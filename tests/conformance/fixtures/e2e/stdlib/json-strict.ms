// conform: tags=optional,records,stdlib-json,testing,try-result
// conform: phase=test
import (
	StringifyOptions, stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",
)

type Handler:
	name: String
	done: Unit
	note: String?

type Plain:
	name: String
	note: String?
	tags: List[Int?]

type Holder:
	items: List[Unit]

test "JSON stringify omits values without a JSON form unless strict":
	handler := Handler("h", unit, none)
	expect_equal(stringify(handler), ok("\{\"name\":\"h\"\}"))?

	invalid: String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
	expect_equal(stringify(handler, StringifyOptions(strict: true)), invalid)?

test "JSON strict stringify rejects no-form list elements":
	holder := Holder([unit])
	expect_equal(stringify(holder), ok("\{\"items\":[null]\}"))?

	invalid: String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
	expect_equal(stringify(holder, StringifyOptions(strict: true)), invalid)?

test "JSON strict stringify accepts none and nulls that are values":
	plain := Plain("p", none, [1, none])
	expected := "\{\"name\":\"p\",\"tags\":[1,null]\}"
	expect_equal(stringify(plain, StringifyOptions(strict: true)), ok(expected.clone()))?
	expect_equal(stringify(plain), ok(expected))?
