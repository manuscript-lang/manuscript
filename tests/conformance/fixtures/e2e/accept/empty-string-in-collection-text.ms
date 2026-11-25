// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "an empty string inside a container shows as quotes" {
	expect_equal([""].to_string(), "[\"\"]")?
	expect_equal("a,,b".split(",").collect().to_string(), "[a, \"\", b]")?
	expect_equal(List[String]().to_string(), "[]")?
}

test "an empty string on its own and in other values" {
	m := Map[String, String]()
	expect_equal("".to_string(), "")?
	expect_equal(f"{["", "x"]}", "[\"\", x]")?
	expect_equal(m.to_string(), "Map()")?
}
