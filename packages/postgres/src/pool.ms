// A connection pool: a fixed set of worker tasks, each owning one connection, fed over
// pipes. A connection cannot move between tasks, so queries travel to the workers and
// rows travel back.
import (
	Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Pipe, ReadStream, WriteStream, pipe from "@std/io/io.ms",

	Config, Conn, Rows, open from "@pg/conn.ms",
	Value from "@pg/value.ms",
)

// One statement and its parameters.
export type Statement:
	sql: String
	params: List[Value] = []

export type Reply:
	rows: Rows
	failure: Error?

fn failed(cause: Error) Reply:
	return Reply(Rows([], [], ""), cause)

// Answers every request with the connect failure.
fn drain(
	cause: Error,
	var requests: ReadStream[Statement],
	var replies: WriteStream[Reply],
) Void!:
	for _request in requests: replies.write(failed(cause.clone()))?
	return replies.close()

// Runs requests on its own connection until the request stream ends.
fn serve(
	var conn: Conn,
	var requests: ReadStream[Statement],
	var replies: WriteStream[Reply],
) Void!:
	for request in requests:
		result := conn.query(request.sql, request.params)

		if result.is_error():
			replies.write(failed(result.err().clone()))?
		else:
			replies.write(Reply(result?, none))?

	conn.close()?
	return replies.close()

// The first and only value on `settings` is the connection config: a promise keeps what
// it captures borrowed unless it is a stream, so the config travels over a pipe too.
fn worker(
	var settings: ReadStream[Config],
	var requests: ReadStream[Statement],
	var replies: WriteStream[Reply],
) Void!:
	config := settings.next()?
	if config.is_none(): return replies.close()

	opened := open(config.get(Config()))
	if opened.is_error(): return drain(opened.err().clone(), var requests, var replies)

	var conn = opened?
	return serve(var conn, var requests, var replies)

export type Slot:
	requests: WriteStream[Statement]
	replies: ReadStream[Reply]
	task: Promise[Void]

// A fixed-size pool; owned by one task. Statements go to workers in turn.
export opaque type Pool:
	slots: List[Slot]
	next: Int

// Starts `size` workers, each opening its own connection.
export fn start(config: Config, size: Int) Pool!:
	var slots = List[Slot]()

	for _i in 0..size:
		var requests = pipe[Statement](capacity: 64)
		var replies = pipe[Reply](capacity: 64)
		var request_writer = requests.writer()
		var reply_writer = replies.writer()
		var request_reader = requests.reader()
		var reply_reader = replies.reader()
		var settings = pipe[Config](capacity: 1)
		var settings_writer = settings.writer()
		var settings_reader = settings.reader()
		settings_writer.write(config.clone())?
		settings_writer.close()?

		task := promise(
			fn: worker(
				var settings_reader,
				var request_reader,
				var reply_writer,
			),
			options: PromiseOptions(placement: Placement.Spread)
		)
		slots.append(Slot(request_writer, reply_reader, task))

	return ok(Pool(slots, 0))

// Queues a statement on the next worker.
fn var Pool.submit(statement: Statement) Int!:
	index := self.next % self.slots.length()
	self.next += 1
	self.slots[index].requests.write(statement.clone())?
	return ok(index)

fn var Pool.take(index: Int) Rows!:
	reply := self.slots[index].replies.next()?
	if reply.is_none(): return error(
		Error("postgres: pool worker stopped", kind: "ECONNRESET")
	)

	got := reply.get(failed(Error("postgres: no reply")))
	if f := got.failure: return error(f.clone())

	return ok(got.rows.clone())

// Runs one statement on a pooled connection.
fn var Pool.query(sql: String, params: List[Value] = []) Rows!:
	index := self.submit(Statement(sql.clone(), params.clone()))?
	return self.take(index)

// Runs statements concurrently across the workers; results are in statement order. The
// first failure is returned after every reply has been read.
fn var Pool.query_all(statements: List[Statement]) List[Rows]!:
	var order = List[Int]()
	for statement in statements: order.append(self.submit(statement.clone())?)

	var results = List[Rows]()
	var failure: Error? = none

	for index in order:
		got := self.take(index)

		if got.is_error():
			failure = got.err().clone()
		else:
			results.append(got?)

	if f := failure: return error(f)

	return ok(results)

// Ends the workers and closes their connections. Closing twice is harmless.
fn var Pool.close() Void!:
	for i in 0..self.slots.length():
		self.slots[i].requests.close()?
	for i in 0..self.slots.length():
		self.slots[i].task.wait()?
	self.slots = []
	return ok(void)
