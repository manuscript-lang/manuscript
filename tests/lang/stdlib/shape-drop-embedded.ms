// conform: tags=testing,tier-stdlib
// conform: phase=test
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

// A record inside a record inside an optional has its leaves where the host puts them. When a later field fails to parse,
// the fields already built are dropped; the drop must read them where they are.
type Inner {
	a Bool
	b Bool
	c Bool
	d Bool
	e Bool
	f Bool
	g Bool
	h Bool
	name String
}

type Mid {
	inner Inner
	n Int
}

type Outer {
	mid Mid?
}

test "a failed parse drops an embedded record it built" {
	text := "{\"mid\":{\"inner\":{\"a\":true,\"b\":false,\"c\":true,\"d\":false,\"e\":true,\"f\":false,\"g\":true,\"h\":false,\"name\":\"abc\"}}}"
	failed := parse[Outer](text)
	expect_equal(failed.is_error(), true)?
}

test "a good parse reads the same shape" {
	text := "{\"mid\":{\"inner\":{\"a\":true,\"b\":false,\"c\":true,\"d\":false,\"e\":true,\"f\":false,\"g\":true,\"h\":false,\"name\":\"abc\"},\"n\":3}}"
	got := parse[Outer](text)?
	expect_equal(got.mid or Mid(inner: Inner(a: false, b: false, c: false, d: false, e: false, f: false, g: false, h: false, name: ""), n: 0), got.mid or Mid(inner: Inner(a: false, b: false, c: false, d: false, e: false, f: false, g: false, h: false, name: ""), n: 0))?
	m := got.mid or Mid(inner: Inner(a: false, b: false, c: false, d: false, e: false, f: false, g: false, h: false, name: ""), n: 0)
	expect_equal(m.n, 3)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
