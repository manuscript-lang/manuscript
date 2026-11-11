import expect_equal, expect_true from "@std/test/test.ms"

// A function of the program named caller_site is an ordinary default, not the test library's
// call-site default.
fn caller_site() Int:
	return 5

fn site(value: Int = caller_site()) Int:
	return value

fn absent(value: Int? = none) Bool:
	return value.is_none()

test "a default named caller_site calls the program's function":
	site() | expect_equal(5)?
	site(value: 2) | expect_equal(2)?

test "an omitted Optional default is none":
	absent() | expect_true()?
	(not absent(value: 2)) | expect_true()?
