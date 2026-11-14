// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn shown[T](value: T) String:
	return value.to_string()

test "a Float32 prints with its own shortest digits":
	a: Float32 := 0.1
	expect_equal(a.to_string(), "0.1")?
	expect_equal("{a}", "0.1")?
	expect_equal(shown(a), "0.1")?
	expect_equal([a].to_string(), "[0.1]")?

test "Float32 arithmetic results print as Float32":
	a: Float32 := 0.1
	c: Float32 := 0.1 + 0.2
	expect_equal((a * a).to_string(), "0.010000001")?
	expect_equal(c.to_string(), "0.3")?
	expect_equal(a.abs().to_string(), "0.1")?

test "Float64 keeps its own digits":
	d: Float64 := 0.1
	expect_equal(d.to_string(), "0.1")?
