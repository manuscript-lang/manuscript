// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Queue from "@std/collections/queue.ms",
	RetryPolicy, map_concurrent, retry from "@std/concurrency/resilience.ms",
	CloseMatchesOptions, UnifiedDiffOptions, close_matches, unified_diff from "@std/data/diff.ms",
	histogram from "@std/data/histogram.ms",
	expect_equal, expect_error from "@std/test/test.ms",
	milliseconds from "@std/time.ms",
)

test "a count of zero or below takes, drops and repeats nothing":
	xs := [1, 2, 3]
	expect_equal(xs.take(-1), List[Int]())?
	expect_equal(xs.drop(-1), [1, 2, 3])?
	expect_equal(xs.repeated(-1), List[Int]())?
	expect_equal(xs.chunks(0), List[List[Int]]())?
	expect_equal(xs.windows(-2), List[List[Int]]())?

test "a queue with no room is always full":
	var queue = Queue[Int](0)
	expect_equal(queue.enqueue(1), false)?
	var negative = Queue[Int](-3)
	expect_equal(negative.enqueue(1), false)?

fn always_fails(attempt Int) Int!String:
	return error(f"try {attempt}")

test "retry runs the operation once when attempts is below one":
	policy := RetryPolicy(attempts: 0, delay: milliseconds(1))
	failure := expect_error(retry(policy, always_fails))?
	expect_equal(failure, "try 1")?

test "map_concurrent with a limit below one is EINVAL":
	failure := expect_error(map_concurrent([1, 2], 0, fn n: n))?
	expect_equal(failure.kind, "EINVAL")?

test "close matches and unified diff accept any limit and context":
	words := ["apple", "ape", "peach"]
	expect_equal(close_matches("appel", words, CloseMatchesOptions(limit: 0)), List[String]())?
	expect_equal(close_matches("appel", words, CloseMatchesOptions(cutoff: 1.5)), List[String]())?
	expect_equal(close_matches("appel", words, CloseMatchesOptions(limit: 1, cutoff: -1.0)), ["apple"])?
	negative := unified_diff(["a", "b"], ["a", "c"], UnifiedDiffOptions(context: -1))
	zero := unified_diff(["a", "b"], ["a", "c"], UnifiedDiffOptions(context: 0))
	expect_equal(negative, zero)?

test "a negative histogram observation counts as zero":
	var h = histogram()
	h.record(-5)
	expect_equal(h.count(), 1)?
	expect_equal(h.percentile(50.0), 0)?
