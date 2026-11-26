// conform: tags=testing,scope-cleanup,tier-io
// conform: phase=test
// Every way a promise can end frees its work and its result: a result kept in the
// promise's row (a small value) or in a block (a wide one), taken or not, and work that
// was queued, running, cancelled or faulted. The leak check runs these tests and counts
// live blocks.
import (
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

type Wide {
	a Int
	b Int
	c Int
	d Int
	text String
}

fn text(n Int) String! {
	return ok("x".repeat(n))
}

fn wide(n Int) Wide! {
	return ok(Wide(a: n, b: n, c: n, d: n, text: "y".repeat(n)))
}

fn nothing() Void! {
	return ok()
}

fn slow(n Int) String! {
	held := "z".repeat(64)
	sleep(milliseconds(n)).wait()?
	return ok(held)
}

fn boom(n Int) String! {
	held := "w".repeat(64)
	xs List[Int] := []
	return ok(f"{held}{xs[n]}")
}

fn nested(n Int) String! {
	inner := promise(() => slow(n))
	return inner.wait()
}

test "a taken result moves out whole" {
	small := promise(() => text(64)).wait()?
	expect_equal(small.length(), 64)?

	big := promise(() => wide(64)).wait()?
	expect_equal(big.a + big.text.length(), 128)?
}

test "a result nobody takes is dropped with its promise" {
	small := promise(() => text(64))
	big := promise(() => wide(64))
	while not small.done() or not big.done() {
		void sleep(milliseconds(1)).wait()
	}
	expect_true(small.done())?
}

test "a promise dropped before it starts frees its work" {
	for i in 0..50 {
		unused := promise(() => text(64 + i))
		unused.cancel()
	}
}

test "a row is clean for the promise that reuses it" {
	for i in 0..50 {
		left := promise(() => text(64))
		while not left.done() {
			void sleep(milliseconds(1)).wait()
		}
	}

	for i in 0..50 {
		promise(() => nothing()).wait()?
	}
}

test "a wait that times out ends and frees the work" {
	late := promise(() => slow(500), options: PromiseOptions(timeout: milliseconds(5)))
	reason := late.wait() | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?
}

test "cancelled work frees what it held" {
	running := promise(() => slow(500))
	void sleep(milliseconds(5)).wait()
	running.cancel()

	reason := running.wait() | expect_error?
	expect_equal(reason.kind, "ECANCELED")?
}

test "cancelling a promise ends the promise it started" {
	outer := promise(() => nested(500))
	void sleep(milliseconds(5)).wait()
	outer.cancel()

	reason := outer.wait() | expect_error?
	expect_equal(reason.kind, "ECANCELED")?
}

test "a fault frees the work and reports once" {
	reason := promise(() => boom(3)).wait() | expect_error?
	expect_equal(reason.kind, "EIO")?
}
// expect-exit: 0
// expect-tests: passed=8 failed=0
