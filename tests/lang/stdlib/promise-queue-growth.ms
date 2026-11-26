// conform: tags=testing,tier-stdlib
// conform: phase=test
import Promise, promise, wait_all, wait_first from "@std/concurrency/promise.ms"
import milliseconds, sleep from "@std/time.ms"
import expect_equal from "@std/test/test.ms"

fn double(n Int) Int! {
	void sleep(milliseconds(n % 7)).wait()?
	return ok(n * 2)
}

fn after(n Int) Int! {
	void sleep(milliseconds(10 + n * 50)).wait()?
	return ok(n)
}

// Thousands of unstarted promises grow the owner's queue ring while other threads take work from it. A grown ring must
// start empty where nothing was copied, or the owner removing an entry a thief already took finds a stale id there,
// believes the work is still its own, and drops the closure a second time (a crash in a Debug build).
test "a ring grown under thieves does not drop a closure twice" {
	var promises List[Promise[Int]] = []
	for i in 0..2000 {
		promises.append(promise(() => double(i)))
	}
	results := wait_all(promises)?
	var sum = 0
	for result in results {
		sum += result
	}
	expect_equal(sum, 3998000)?
	var later List[Promise[Int]] = []
	for i in 0..50 {
		later.append(promise(() => after(i)))
	}
	expect_equal(wait_first(later)?, 0)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
