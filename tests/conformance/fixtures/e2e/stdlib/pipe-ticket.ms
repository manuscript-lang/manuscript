// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	ReadStream, Ticket, WriteStream, pipe from "@std/io/io.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

// What a caller sends a running worker: a count and a ticket for the pipe to answer on.
type Ask:
	count: Int
	rows: Ticket[Int]

// Answers each ask by opening its ticket and writing 1..count.
fn worker(var asks: ReadStream[Ask]) Void!:
	for ask in asks:
		var rows = ask.rows.open()?
		for n in 1..ask.count + 1: rows.write(n)?
		rows.close()?
	return ok()

fn drain(var input: ReadStream[Int]) List[Int]!:
	var seen: List[Int] = []
	for item in input: seen.append(item)
	return ok(seen)

test "a running task writes to a pipe made after it started, through a ticket":
	var requests = pipe[Ask](capacity: 4)
	var request_writer = requests.writer()
	var request_reader = requests.reader()
	task := promise(fn: worker(var request_reader))

	var first = pipe[Int](capacity: 8)
	request_writer.write(Ask(3, first.ticket()?))?
	var second = pipe[Int](capacity: 8)
	request_writer.write(Ask(2, second.ticket()?))?

	var first_reader = first.reader()
	expect_equal(drain(var first_reader)?, [1, 2, 3])?
	var second_reader = second.reader()
	expect_equal(drain(var second_reader)?, [1, 2])?
	request_writer.close()?
	task.wait()?

test "a ticket opens once":
	var rows = pipe[Int](capacity: 4)
	ticket := rows.ticket()?
	var writer = ticket.open()?
	writer.write(7)?
	writer.close()?
	failure := expect_error(ticket.open())?
	expect_equal(failure.kind, "EBADF")?
	var seen = rows.reader()
	expect_equal(drain(var seen)?, [7])?

test "a ticket keeps the reader waiting until it is opened and closed":
	var rows = pipe[Int](capacity: 4)
	ticket := rows.ticket()?
	var reader = rows.reader()
	var writer = ticket.open()?
	writer.write(1)?
	writer.close()?
	expect_equal(drain(var reader)?, [1])?

test "closing the reader releases tickets nobody opened":
	var rows = pipe[Int](capacity: 4)
	ticket := rows.ticket()?
	var reader = rows.reader()
	reader.close()?
	failure := expect_error(ticket.open())?
	expect_equal(failure.kind, "EBADF")?
	late := expect_error(rows.ticket())?
	expect_equal(late.kind, "EBADF")?
