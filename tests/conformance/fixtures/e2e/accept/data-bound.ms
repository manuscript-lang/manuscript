// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Data from "@std/core.ms",
	JsonEncode, JsonValue, stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",
)

type Plain:
	name: String
	tags: List[String]
	note: String?

type Money:
	cents: Int

fn Money.to_json() JsonValue:
	return JsonValue.StringValue("usd:{self.cents}")

enum Mode:
	Fast
	Slow

fn text[T: Data](value: T) String:
	return stringify(value).get("")

test "Data accepts plain records, lists, codecs, and JSON documents":
	plain := Plain("a", ["x"], none)
	expect_equal(text(plain), "\{\"name\":\"a\",\"tags\":[\"x\"]\}")?
	expect_equal(text(Money(5)), "\"usd:5\"")?
	expect_equal(text(Mode.Fast), "\"Fast\"")?
	expect_equal(text(JsonValue.Null), "null")?
	expect_equal(text([1, 2, 3]), "[1,2,3]")?
