import expect_equal from "@std/test.ms"
import IoError, LineReader, lines from "@std/io.ms"
import Iterator from "@std/core.ms"
import MemoryStream from "./support/streams.ms"

fn collect(text: String, max_bytes: Optional[Int] = none) Result[List[String], IoError]:
    var reader = lines(MemoryStream(text.to_bytes(), 0, closed: false), max_bytes)
    var seen: List[String] = []
    for line in reader:
        seen.append(line.clone())
    if let failure = reader.error():
        return error(failure)

    return ok(seen)

test "an empty stream has no lines":
    try expect_equal(collect(""), ok([]))

test "lines drop terminators and keep an unterminated last line":
    try expect_equal(collect("one\r\ntwo\n\nlast"), ok(["one", "two", "", "last"]))

test "a final newline adds no empty line":
    try expect_equal(collect("a\nb\n"), ok(["a", "b"]))

test "an over-budget line stops the loop and sets the error":
    var reader = lines(
        MemoryStream("ok\ntoo long line\nnever".to_bytes(), 0, closed: false), 5
    )
    var seen: List[String] = []
    for line in reader:
        seen.append(line.clone())
    try expect_equal(seen, ["ok"])
    try expect_equal(reader.error(), some(IoError.LimitExceeded))

test "a closed stream ends the loop with its error":
    var reader = lines(MemoryStream("a\n".to_bytes(), 0, closed: true))
    var count = 0
    for line in reader:
        count += 1
    try expect_equal(count, 0)
    try expect_equal(reader.error(), some(IoError.Closed))

test "break and continue work in an iterator loop":
    var reader = lines(MemoryStream("1\nskip\n3\n4\n".to_bytes(), 0, closed: false))
    var seen: List[String] = []

    for line in reader:
        if line == "skip":
            continue
        if line == "4":
            break

        seen.append(line.clone())

    try expect_equal(seen, ["1", "3"])

type Countdown:
    left: Int

impl Iterator[Int] for Countdown:
    var fn next() Optional[Int]:
        if self.left == 0:
            return none

        self.left -= 1
        return some(self.left + 1)

test "any Iterator implementation works, including a temporary":
    var total = 0
    for n in Countdown(3):
        total += n
    try expect_equal(total, 6)

test "an iterator behind the Iterator interface works":
    var source: Iterator[Int] = Countdown(2)
    var seen: List[Int] = []
    for n in source:
        seen.append(n)
    try expect_equal(seen, [2, 1])
