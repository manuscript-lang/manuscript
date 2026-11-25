// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Pt {
	x, y Int
}

type Wide {
	a, b, c, d Int
	label String
}

// Lookups of a map whose value is wider than a word run as an in-line probe over the same slot layout the runtime uses:
// presence, the address of an entry read through an index, and an update that changes the value in place.
test "an Int-key map with a two-word value answers presence and entries" {
	var points Map[Int, Pt] = {}
	for n in 0..50 {
		points.add(n * 3, Pt(x: n, y: n * n))
	}

	var seen = 0
	for n in 0..150 {
		if points.contains(n) {
			seen += 1
			expect_equal(points[n].x * 3, n)?
		}
	}
	expect_equal(seen, 50)?
	expect_equal(points.contains(-1), false)?
}

test "a String-key map with an owning wide value answers presence and entries" {
	var items Map[String, Wide] = {}
	for n in 0..30 {
		items.add(f"key{n}", Wide(a: n, b: n + 1, c: n + 2, d: n + 3, label: f"label{n}"))
	}

	expect_equal(items.contains("key29"), true)?
	expect_equal(items.contains("key30"), false)?
	expect_equal(items["key7"].d, 10)?
	expect_equal(items["key7"].label, "label7")?
}

test "update of a wide scalar value changes it in place and appends a missing key" {
	var points Map[String, Pt] = {}
	for n in 0..20 {
		points.update(f"p{n % 4}", Pt(x: 0, y: 0), p => Pt(x: p.x + 1, y: p.y + n))
	}

	expect_equal(points.length(), 4)?
	expect_equal(points["p0"].x, 5)?
	expect_equal(points["p3"].y, 3 + 7 + 11 + 15 + 19)?
}
