// conform: tags=testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `&T` written as a type argument is a real type: a borrow reads as its value, and passes where the value is read.

fn total_length(words List[&String]) Int {
	var total = 0
	for word in words {
		total += word.length()
	}
	return total
}

fn first_length(words List[&String]) Int {
	return words[0].length()
}

test "a list of views reads like a list of strings" {
	views := "ab,cde,f".split(",").collect()
	expect_equal(total_length(views), 6)?
	expect_equal(first_length(views), 2)?
}

test "a list of views passes where a list of strings is read" {
	views := "ab,cde".split(",").collect()
	expect_equal(views.map(w => w.length()), [2, 3])?
	expect_equal(views.filter(w => w.length() > 2), ["cde"])?
}
