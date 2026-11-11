import (
	Bytes from "@std/bytes.ms",
	Iterator from "@std/core.ms",
	ReadStream from "@std/io/io.ms",
	collect, lines from "@std/io/streams.ms",
	expect_equal from "@std/test/test.ms",

	closed_reader, memory from "./support/streams.ms",
)

fn gather(input: ReadStream[Bytes], max_bytes: Int? = none) List[String]!:
	return collect(lines(input, max_bytes), none)

test "an empty stream has no lines":
	expect_equal(gather(memory("")), ok([]))?

test "lines drop terminators and keep an unterminated last line":
	expect_equal(gather(memory("one\r\ntwo\n\nlast")), ok(["one", "two", "", "last"]))?

test "a final newline adds no empty line":
	expect_equal(gather(memory("a\nb\n")), ok(["a", "b"]))?

test "an over-budget line fails the read after the lines before it":
	var input = lines(memory("ok\ntoo long line\nnever"), 5)
	var seen: List[String] = []
	var failure: Error? = none

	while true:
		step := input.next()

		if step.is_error():
			failure = step.err()
			break

		if line := step.get():
			seen.append(line.clone())
		else:
			break

	expect_equal(seen, ["ok"])?
	expect_equal(failure, Error("I/O: limit exceeded", kind: "EOVERFLOW"))?

test "a closed stream fails the first read with its error":
	var input = lines(closed_reader())
	step := input.next()
	expect_equal(step, error(Error("I/O: resource is closed", kind: "EBADF")))?

test "break and continue work in a stream loop":
	var seen: List[String] = []

	for line in lines(memory("1\nskip\n3\n4\n")):
		text := line
		if text == "skip": continue
		if text == "4": break

		seen.append(text.clone())

	expect_equal(seen, ["1", "3"])?

type Countdown:
	left: Int

impl Iterator[Int] for Countdown:
	var fn next() Int?:
		if self.left == 0: return none

		self.left -= 1
		return (self.left + 1)

test "any Iterator implementation works, including a temporary":
	var total = 0
	for n in Countdown(3):
		total += n
	expect_equal(total, 6)?

test "an iterator behind the Iterator interface works":
	var source: Iterator[Int] = Countdown(2)
	var seen: List[Int] = []
	for n in source:
		seen.append(n)
	expect_equal(seen, [2, 1])?
