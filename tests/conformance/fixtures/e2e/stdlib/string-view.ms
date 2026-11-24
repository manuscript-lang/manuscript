// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Whether `[a, b)` (negative bounds count from the end) lies inside the text on scalar
// boundaries, so `view` accepts it and equals `slice`.
fn whole_range(text String, a Int, b Int) Bool:
	n := text.length()
	from := if a < 0: n + a else: a
	to := if b < 0: n + b else: b
	if from < 0 or to < from or to > n: return false
	return (from == n or text.scalar_at(from, -1) != -1) and (to == n or text.scalar_at(to, -1) != -1)

test "view borrows a range of bytes without copying":
	text := "banana héllo wörld, a long string that is not inline"
	expect_equal(text.view(2, 6), "nana")?
	expect_equal(text.view(7, 13), "héllo")?
	expect_equal(text.view(-6, text.length()), "inline")?
	expect_equal(text.view(0, text.length()), text)?
	expect_equal(text.view(3, 3).length(), 0)?

test "view agrees with slice":
	text := "aé🙂z héllo wörld and a longer tail of ascii text"
	var a = -text.length()

	while a <= text.length():
		var b = a

		while b <= text.length():
			if whole_range(text, a, b):
				expect_equal(text.view(a, b).clone(), text.slice(a, b))?
			b += 7

		a += 5

test "a kept view is a copy made with clone":
	text := "hello world, a string long enough to live on the heap"
	var words = List[String]()
	words.append(text.view(6, 11).clone())
	words.append(text.view(0, 5).clone())
	expect_equal(words, ["world", "hello"])?

test "view of a temporary is owned":
	tail := "hello".upper().view(1, 5)
	expect_equal(tail, "ELLO")?

test "view of a short text agrees with slice for ASCII and non-ASCII":
	for source in ["abcdefghijklmno", "aé🙂z", "héllo", "", "x"]:
		text := source.upper().lower()
		var a = 0

		while a <= text.length():
			var b = a

			while b <= text.length():
				if whole_range(text, a, b):
					expect_equal(text.view(a, b).clone(), text.slice(a, b))?
				b += 1

			a += 1
