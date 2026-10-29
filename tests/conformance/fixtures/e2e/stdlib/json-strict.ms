# conform: tags=optional,records,stdlib-json,testing,try-result
# conform: phase=test
import expect_equal from "@std/test.ms"
import {stringify, JsonError} from "@std/json.ms"

type Handler:
    name: String
    done: Unit
    note: Optional[String]

type Plain:
    name: String
    note: Optional[String]
    tags: List[Optional[Int]]

type Holder:
    items: List[Unit]
    named: Map[String, Unit]

test "JSON stringify omits values without a JSON form unless strict":
    let handler = Handler("h", unit, none)
    try expect_equal(stringify(handler), ok("\{\"name\":\"h\"\}"))

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(handler, strict: true), invalid)

test "JSON strict stringify rejects no-form list elements and map values":
    let holder = Holder([unit], Map[String, Unit]())
    try expect_equal(stringify(holder), ok("\{\"items\":[null],\"named\":\{\}\}"))

    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(holder, strict: true), invalid)

    var named = Map[String, Unit]()
    named.add("a", unit)
    try expect_equal(stringify(Holder([], named), strict: true), invalid)

test "JSON strict stringify accepts none and nulls that are values":
    let plain = Plain("p", none, [some(1), none])
    let expected = "\{\"name\":\"p\",\"tags\":[1,null]\}"
    try expect_equal(stringify(plain, strict: true), ok(expected.clone()))
    try expect_equal(stringify(plain), ok(expected))
