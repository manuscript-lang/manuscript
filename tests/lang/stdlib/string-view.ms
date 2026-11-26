// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import msrt_test_edge_string from "@std/internal/test.ms"

// Whether `[a, b)` (negative bounds count from the end) lies inside the text on scalar
// boundaries, so `view` accepts it and equals `slice`.
fn whole_range(text String, a Int, b Int) Bool {
	n := text.length()
	from := if a < 0 { n + a } else { a }
	to := if b < 0 { n + b } else { b }
	if from < 0 or to < from or to > n { return false }

	return (
		(from == n or text.scalar_at(from, -1) != -1)
		and (to == n or text.scalar_at(to, -1) != -1)
	)
}

test "view borrows a range of bytes without copying" {
	text := "banana héllo wörld, a long string that is not inline"
	expect_equal(text.view(2, 6), "nana")?
	expect_equal(text.view(7, 13), "héllo")?
	expect_equal(text.view(-6, text.length()), "inline")?
	expect_equal(text.view(0, text.length()), text)?
	expect_equal(text.view(3, 3).length(), 0)?
}

test "view agrees with slice" {
	text := "aé🙂z héllo wörld and a longer tail of ascii text"
	var a = -text.length()

	while a <= text.length() {
		var b = a

		while b <= text.length() {
			if whole_range(text, a, b) {
				expect_equal(text.view(a, b).clone(), text.slice(a, b))?
			}
			b += 7
		}

		a += 5
	}
}

test "a kept view is a copy made with clone" {
	text := "hello world, a string long enough to live on the heap"
	var words = List[String]()
	words.append(text.view(6, 11).clone())
	words.append(text.view(0, 5).clone())
	expect_equal(words, ["world", "hello"])?
}

test "view of a temporary is owned" {
	tail := "hello".upper().view(1, 5)
	expect_equal(tail, "ELLO")?
}

test "view of a short text agrees with slice for ASCII and non-ASCII" {
	for source in ["abcdefghijklmno", "aé🙂z", "héllo", "", "x"] {
		text := source.upper().lower()
		var a = 0

		while a <= text.length() {
			var b = a

			while b <= text.length() {
				if whole_range(text, a, b) {
					expect_equal(text.view(a, b).clone(), text.slice(a, b))?
				}
				b += 1
			}

			a += 1
		}
	}
}

// A string owes nothing after its last byte: these texts end where the next page is unreadable, so a fast path that
// reads the byte after the end (to find a scalar boundary) faults on every run.
test "slice and view to the end of a string read no byte past it" {
	var text = ""
	var i = 0

	while i < 24 {
		text = f"{text}é"
		edge := msrt_test_edge_string(text)
		n := edge.length()
		var from = 0

		while from <= n {
			expect_equal(edge.slice(from, n).length(), n - (from + from % 2))?
			expect_equal(edge.slice(from, n), text.slice(from, n))?
			from += 1
		}
		var at = 0

		while at <= n {
			if whole_range(edge, at, n) {
				expect_equal(edge.view(at, n).clone(), text.slice(at, n))?
			}
			at += 1
		}
		i += 1
	}
}

// The same texts through the other string operations that have a fast path: each result must equal the one from an
// ordinary copy, and none may read past the end.
test "string operations read no byte past the end of a string" {
	var text = ""
	var i = 0

	while i < 40 {
		text = f"{text}{if i % 3 == 0 { "é" } else { "a" }}"
		edge := msrt_test_edge_string(text)
		same := text.clone()
		expect_equal(edge == same, true)?
		expect_equal(edge < same, false)?
		expect_equal(edge.contains("a"), same.contains("a"))?
		expect_equal(edge.starts_with("é"), same.starts_with("é"))?
		expect_equal(edge.ends_with("a"), same.ends_with("a"))?
		expect_equal(edge.index_of("é"), same.index_of("é"))?
		expect_equal(edge.trim(), same.trim())?
		expect_equal(edge.upper(), same.upper())?
		expect_equal(edge.replace("a", "b"), same.replace("a", "b"))?
		expect_equal(edge.split("é").collect().length(), same.split("é").collect().length())?
		expect_equal(f"{edge}{edge}", f"{same}{same}")?
		expect_equal(edge.slice(1, -1), same.slice(1, -1))?
		var count = 0

		for c in edge.chars() {
			count += c.length()
		}
		expect_equal(count, same.length())?
		i += 1
	}
}

// expect-exit: 0
// expect-tests: passed=7 failed=0
