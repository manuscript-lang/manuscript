# conform: tags=optional,records,stdlib-json,testing,try-result
# conform: phase=test
from "@std/testing.ms" import expect_equal
from "@std/json.ms" import stringify, JsonError

type Handler:
    name: String
    callback: Callable[[], Int]
    note: Optional[String]

type Plain:
    name: String
    note: Optional[String]
    tags: List[Optional[Int]]

type Holder:
    items: List[Callable[[], Int]]
    named: Map[String, Callable[[], Int]]

def one() -> Int:
    return 1

test "JSON stringify omits values without a JSON form unless strict":
    let handler = Handler("h", one, none)
    try expect_equal(stringify(handler), ok("{\"name\":\"h\"}"))
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(handler, strict: True), invalid)

test "JSON strict stringify rejects no-form list elements and map values":
    let holder = Holder([one], Map[String, Callable[[], Int]]())
    try expect_equal(stringify(holder), ok("{\"items\":[null],\"named\":{}}"))
    let invalid: Result[String, JsonError] = error(JsonError.InvalidData)
    try expect_equal(stringify(holder, strict: True), invalid)
    var named = Map[String, Callable[[], Int]]()
    named.add("a", one)
    try expect_equal(stringify(Holder([], named), strict: True), invalid)

test "JSON strict stringify accepts none and nulls that are values":
    let plain = Plain("p", none, [some(1), none])
    let expected = "{\"name\":\"p\",\"tags\":[1,null]}"
    try expect_equal(stringify(plain, strict: True), ok(expected.clone()))
    try expect_equal(stringify(plain), ok(expected))
