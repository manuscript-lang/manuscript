import (
	Closeable from "@std/core.ms",
	WriteStream, stderr, stdout from "@std/io/io.ms",
	expect_equal, fail from "@std/test/test.ms",
)

type Resource:
	label: String
	output: WriteStream[String]
	done: Bool = false

// Idempotent, as the Closeable contract requires: the block that ends early closes by
// hand and the scope closes again.
fn var Resource.close() Unit!:
	if self.done: return ok(unit)

	self.done = true

	_ := self.output.write(value: "close {self.label}\n")

type Pair:
	first: Int
	second: Int

fn report(var output: WriteStream[String], label: String, value: Int) Int:
	_ := output.write(value: "{label}\n")
	return value

fn combine(first: Int, second: Int) Int:
	return first + second

fn select(var output: WriteStream[String]) fn(Int, Int) Int:
	_ := output.write(value: "callable\n")
	return combine

fn early(var output: WriteStream[String]) Int:
	_outer := Resource(label: "outer", output: stdout())
	_inner := Resource(label: "inner", output: stdout())
	return report(output: var output, label: "return value", value: 5)

fn failure() Int!Error:
	return error(Error("expected"))

fn propagate(output: WriteStream[String]) Int!Error:
	_resource := Resource(label: "propagation", output: output)
	number := failure()?
	return ok(number)

fn iterable(var output: WriteStream[String]) List[Int]:
	_ := output.write(value: "iterable\n")
	return [1, 2]

fn exercise() Int!:
	var chosen = stdout()
	var second_out = stdout()
	var first_out = stdout()
	total := select(output: var chosen)(
		report(output: var second_out, label: "second", value: 2),
		report(output: var first_out, label: "first", value: 1),
	)
	total | expect_equal(3)?

	var pair_second_out = stdout()
	var pair_first_out = stdout()
	pair := Pair(
		second: report(
			output: var pair_second_out,
			label: "pair second",
			value: 2,
		),
		first: report(output: var pair_first_out, label: "pair first", value: 1),
	)
	(pair.first + pair.second) | expect_equal(3)?

	var _resource = Resource(label: "normal", output: stdout())
	_completed := unit
	_resource.close()?

	_ := stdout().write(value: "after normal\n")
	var count = 0

	while count < 2:
		_resource := Resource(label: "iteration", output: stdout())
		count += 1
		continue

	var iterable_out = stdout()

	for value in iterable(output: var iterable_out):
		_resource := Resource(label: "break", output: stdout())
		break

	match propagate(output: stdout()):
		ok(_):
			fail(message: "Unexpected case")?
		error(_):
			_completed := unit

	var early_out = stdout()
	early(output: var early_out) | expect_equal(5)?

	_ := stdout().write(value: "finished\n")
	return ok(0)

export fn main() Int:
	match exercise():
		ok(status): return status
		error(cause):
			_written := stderr().write("{cause.message}\n")
			return 1
