// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	ReadStream, Source, WriteStream, pipe from "@std/io/io.ms",
	collect, copy, from_list, map from "@std/io/streams.ms",
	expect_equal from "@std/test/test.ms",
)

// Counts up to `stop`, fails once at `fail_at`, and reports where it was when closed.
type Counter:
	at: Int
	stop: Int
	fail_at: Int
	closes: WriteStream[Int]

fn var Counter.next() Int?!:
	if self.at == self.fail_at:
		self.at += 1
		return error(Error("boom", kind: "EIO"))

	if self.at >= self.stop: return ok(none)

	self.at += 1
	return ok(self.at)

fn var Counter.close() Unit!:
	self.closes.write(self.at)?

test "a loop that breaks hands the source back to its stream":
	var closes = pipe[Int](capacity: 8)
	var s = ReadStream[Int](Counter(0, 5, -1, closes.writer()))
	var seen: List[Int] = []

	for x in s:
		seen.append(x)
		if seen.length() == 2: break

	next := s.next()?
	expect_equal(next.get(-1), 3)?
	for x in s:
		seen.append(x)
	expect_equal(seen, [1, 2, 4, 5])?
	s.close()?
	expect_equal(closes.receive()?, 5)?

test "an error ends the loop and the stream reads on":
	var closes = pipe[Int](capacity: 8)
	var s = ReadStream[Int](Counter(0, 3, 1, closes.writer()))
	var failures = 0

	while true:
		item := s.next()

		if item.is_error():
			failures += 1
			break

		if item.get().is_none(): break

	expect_equal(failures, 1)?

	next := s.next()?
	expect_equal(next.get(-1), 3)?

test "closing the stream inside its loop still closes the source once":
	var closes = pipe[Int](capacity: 8)
	var s = ReadStream[Int](Counter(0, 4, -1, closes.writer()))
	for x in s:
		if x == 2:
			s.close()?
	expect_equal(closes.receive()?, 2)?

test "stages pull directly and keep their results":
	doubled := collect(from_list([1, 2, 3]) | map(fn v: v * 2), none)?
	expect_equal(doubled, [2, 4, 6])?

	limited := collect(from_list([1, 2, 3]), 2)
	expect_equal(limited.err().kind, "EOVERFLOW")?

test "copy moves every item":
	var out = pipe[Int](capacity: 8)
	var writer = out.writer()
	count := copy(from_list([7, 8, 9]), writer)?
	expect_equal(count, 3)?
