// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	ReadStream, Source from "@std/io/io.ms",
	filter, map, take from "@std/io/steps.ms",
	collect, fold, from_list from "@std/io/streams.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

// An endless source that counts how many items were pulled.
type Counting {
	next_value Int
	pulled Int
}

fn var Counting.next() Int?! {
	self.pulled += 1
	self.next_value += 1
	return ok(self.next_value)
}

fn move Counting.close() Void! {
	return ok()
}

test "filter keeps matching items in order" {
	kept := collect(from_list([1, 2, 3, 4, 5, 6]) | filter(x => x % 2 == 0), null)?
	expect_equal(kept, [2, 4, 6])?
	expect_equal(
		collect(from_list([1, 3]) | filter(x => x % 2 == 0), null)?,
		List[Int](),
	)?
}

test "take stops after count items and never reads past them" {
	first := collect(ReadStream[Int](Counting(0, 0)) | take(3), null)?
	expect_equal(first, [1, 2, 3])?
	expect_equal(collect(from_list([1, 2]) | take(5), null)?, [1, 2])?
	expect_equal(collect(from_list([1, 2]) | take(0), null)?, List[Int]())?
	expect_equal(collect(from_list([1, 2]) | take(-1), null)?, List[Int]())?
}

test "fold combines items from a start value" {
	expect_equal(fold(from_list([1, 2, 3, 4]), 10, (s, x) => s + x)?, 20)?
	expect_equal(fold(from_list(List[Int]()), 7, (s, x) => s + x)?, 7)?
}

test "stages compose over an endless stream" {
	out := collect(
		ReadStream[Int](Counting(0, 0)) | filter(x => x > 2) | map(
			x => x * 10
		) | take(3),
		null,
	)?
	expect_equal(out, [30, 40, 50])?
}

// Every odd read fails; successful reads yield 2, 4, 6, ... without ending.
type Intermittent {
	calls Int = 0
}

fn var Intermittent.next() Int?! {
	self.calls += 1
	if self.calls % 2 == 1 { return error(Error("retry this read", kind: "EAGAIN")) }

	return ok(self.calls)
}

fn move Intermittent.close() Void! {
	return ok()
}

test "take does not spend its last item on a failed read" {
	var source = ReadStream[Int](Intermittent()) | take(1)
	reason := source.next() | expect_error?
	expect_equal(reason, Error("retry this read", kind: "EAGAIN"))?
	expect_equal(source.next()?, 2)?
	expect_equal(source.next()?, null)?
	expect_equal(source.next()?, null)?
}

test "take preserves its remaining items across errors in composed stages" {
	var source = (
		ReadStream[Int](Intermittent())
		| filter(x => x % 4 == 0)
		| map(x => x * 10)
		| take(2)
	)

	for expected in [40, 80] {
		for failed in 0..2 {
			reason := source.next() | expect_error?
			expect_equal(reason, Error("retry this read", kind: "EAGAIN"))?
		}

		expect_equal(source.next()?, expected)?
	}

	// The endless input's next call would fail; the exhausted taker must not pull it.
	expect_equal(source.next()?, null)?
	expect_equal(source.next()?, null)?
}
