import expect_true from "@std/test/test.ms"

fn deep(n Int) Int {
	return deep(n + 1) + 1
}

fn divide(a, b Int) Int {
	return a / b
}

fn level2(b Int) Int {
	return divide(10, b)
}

fn level1(b Int) Int {
	return level2(b)
}

test "division" {
	x := level1(0)
	expect_true(x == 0)?
}
