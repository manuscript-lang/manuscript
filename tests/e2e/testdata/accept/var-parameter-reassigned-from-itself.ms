import expect_equal from "@std/test/test.ms"

// A var parameter is the caller's value and cannot be moved out of the function, except into
// the right side of an assignment to itself, which refills it before the caller sees it.

interface Counter:
	var fn bump() Unit
	fn count() Int

type Box:
	n: Int

fn var Box.bump() Unit:
	self.n += 1

fn Box.count() Int:
	return self.n

// Passes everything on to `inner` and counts the calls it saw.
type Wrap:
	inner: Counter
	calls: Int

fn var Wrap.bump() Unit:
	self.inner.bump()
	self.calls += 1

fn Wrap.count() Int:
	return self.inner.count() * 10 + self.calls

fn twice(var c: Counter) Unit:
	c.bump()
	c.bump()

fn wrapped(var c: Counter, next: fn(var Counter) Unit) Unit:
	// The wrapper owns the counter it was handed and takes its place.
	c = Wrap(inner: c, calls: 0)
	next(var c)

fn rewrap(var xs: List[Int]) Unit:
	xs = [xs.length(), xs[0]]

test "a var parameter of an interface type is wrapped in place":
	var b: Counter = Box(n: 0)
	twice(var b)
	wrapped(var b, twice)
	b.count() | expect_equal(42)?

test "the concrete receiver is recovered by a contract type match":
	var b: Counter = Box(n: 0)
	wrapped(var b, twice)

	match b:
		Wrap(w): w.calls | expect_equal(2)?
		_: 0 | expect_equal(1)?

test "a var parameter of a one-owner type is rebuilt from itself":
	var xs = [7, 2, 3]
	rewrap(var xs)
	xs | expect_equal([3, 7])?
