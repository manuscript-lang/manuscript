// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A split whose list is only read in place makes no heap list: element 0 is found
// without the list, and a short text with few pieces splits into the frame. Every other
// shape keeps the list and must agree with it.
fn first_of(line String) String {
	return line.split(" ").collect()[0].clone()
}

fn fields(line String) Int {
	parts := line.split(" ").collect()
	var total = 0
	for i in 0..parts.length() {
		total += parts[i].length()
	}
	return total
}

fn kept(line String) List[String] {
	parts := line.split(" ").collect()
	return parts.clone()
}

test "the first piece of a split" {
	expect_equal(first_of("a b c"), "a")?
	expect_equal(first_of("abc"), "abc")?
	expect_equal(first_of(" b"), "")?
	expect_equal(first_of(""), "")?
	expect_equal(
		first_of("a-long-first-field-over-fifteen-bytes b"),
		"a-long-first-field-over-fifteen-bytes",
	)?
}

test "pieces in the frame and past it" {
	expect_equal(fields("a bb ccc"), 6)?
	expect_equal(fields("1 2 3 4 5 6 7 8"), 8)?
	expect_equal(fields("1 2 3 4 5 6 7 8 9"), 9)?
	expect_equal(fields("1 2 3 4 5 6 7 8 9 10 11 12"), 15)?
	expect_equal(fields(""), 0)?

	long := "word ".repeat(40)
	expect_equal(fields(long), 160)?
}

test "a list that leaves the function keeps its pieces" {
	expect_equal(kept("x yy zzz"), ["x", "yy", "zzz"])?
	expect_equal(
		kept("1 2 3 4 5 6 7 8 9"),
		["1", "2", "3", "4", "5", "6", "7", "8", "9"],
	)?
}

test "a piece longer than a short string is read in the loop that made it" {
	var seen = 0

	for line in ["alpha-bravo-charlie-delta one two", "three four"] {
		f := line.split(" ").collect()
		seen += f[0].length() + f.length()
	}

	expect_equal(seen, 25 + 3 + 5 + 2)?
}
