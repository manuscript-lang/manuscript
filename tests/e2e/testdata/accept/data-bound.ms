import expect_equal from "@std/test.ms"
import Data from "@std/core.ms"
import JsonEncode, JsonValue, stringify from "@std/json.ms"

type Plain:
    name: String
    tags: List[String]
    note: String?

type Money:
    cents: Int

impl JsonEncode for Money:
    fn to_json() JsonValue:
        return JsonValue.StringValue("usd:{self.cents}")

type Mode:
    case Fast
    case Slow

fn text[T: Data](value: T) String:
    return stringify(value).get("")

test "Data accepts plain records, lists, codecs, and JSON documents":
    let plain = Plain("a", ["x"], none)
    try expect_equal(text(plain), "\{\"name\":\"a\",\"tags\":[\"x\"]\}")
    try expect_equal(text(Money(5)), "\"usd:5\"")
    try expect_equal(text(Mode.Fast), "\"Fast\"")
    try expect_equal(text(JsonValue.Null), "null")
    try expect_equal(text([1, 2, 3]), "[1,2,3]")
