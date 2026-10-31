# conform: tags=optional,records,stdlib-json,testing,try-result
# conform: phase=test
import expect_equal from "@std/test.ms"
import stringify, JsonError from "@std/json.ms"

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
    let handler = Handler("h", unit, none)
    try expect_equal(stringify(handler), ok("\{\"name\":\"h\"\}"))

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(handler, strict: true), invalid)

test "JSON strict stringify rejects no-form list elements":
    let holder = Holder([unit])
    try expect_equal(stringify(holder), ok("\{\"items\":[null]\}"))

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(holder, strict: true), invalid)

test "JSON strict stringify accepts none and nulls that are values":
    let plain = Plain("p", none, [1, none])
    let expected = "\{\"name\":\"p\",\"tags\":[1,null]\}"
    try expect_equal(stringify(plain, strict: true), ok(expected.clone()))
    try expect_equal(stringify(plain), ok(expected))
