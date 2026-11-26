// conform: tags=aliasing,closures,control-flow,formatter,interfaces,interpolation,lists,match,modules,mutation,parser,records,stdlib-cleanup,stdlib-errors,stdlib-io,stdlib-testing,strings,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/projects/lifecycle/main.ms
import (
	Closeable from "@std/core.ms",
	WriteStream, stderr, stdout from "@std/io/io.ms",
	expect_equal, fail from "@std/test/test.ms",
)

type Resource {
	label String
	output WriteStream[String]
	done Bool = false
}

// Idempotent, as the Closeable contract requires: the block that ends early closes by
// hand and the scope closes again.
fn move Resource.close() Void! {
	if self.done { return ok() }

	self.done = true
	void self.output.write(value: f"close {self.label}\n")
}

type Pair {
	first Int
	second Int
}

fn report(var output WriteStream[String], label String, value Int) Int {
	void output.write(value: f"{label}\n")
	return value
}

fn combine(first Int, second Int) Int {
	return first + second
}

fn select(var output WriteStream[String]) fn(Int, Int) Int {
	void output.write(value: "callable\n")
	return combine
}

fn early(var output WriteStream[String]) Int {
	_outer := Resource(label: "outer", output: stdout())
	_inner := Resource(label: "inner", output: stdout())
	return report(output: output, label: "return value", value: 5)
}

fn failure() Int!Error {
	return error(Error("expected"))
}

fn propagate(move output WriteStream[String]) Int!Error {
	_resource := Resource(label: "propagation", output: output)
	number := failure()?
	return ok(number)
}

fn iterable(var output WriteStream[String]) List[Int] {
	void output.write(value: "iterable\n")
	return [1, 2]
}

fn exercise() Int! {
	var chosen = stdout()
	var second_out = stdout()
	var first_out = stdout()
	total := select(output: chosen)(
		report(output: second_out, label: "second", value: 2),
		report(output: first_out, label: "first", value: 1),
	)
	total | expect_equal(3)?

	var pair_second_out = stdout()
	var pair_first_out = stdout()
	pair := Pair(
		second: report(output: pair_second_out, label: "pair second", value: 2),
		first: report(output: pair_first_out, label: "pair first", value: 1),
	)
	(pair.first + pair.second) | expect_equal(3)?

	var _resource = Resource(label: "normal", output: stdout())
	_completed := void
	_resource.close()?
	void stdout().write(value: "after normal\n")

	var count = 0

	while count < 2 {
		_resource := Resource(label: "iteration", output: stdout())
		count += 1
		continue
	}

	var iterable_out = stdout()

	for value in iterable(output: iterable_out) {
		_resource := Resource(label: "break", output: stdout())
		break
	}

	match propagate(output: stdout()) {
		ok(_) => {
			fail(message: "Unexpected case")?
		}
		error(_) => {
			_completed := void
		}
	}

	var early_out = stdout()
	early(output: early_out) | expect_equal(5)?
	void stdout().write(value: "finished\n")
	return ok(0)
}

export fn main() Int {
	match exercise() {
		ok(status) => return status
		error(cause) => {
			_written := stderr().write(f"{cause.message}\n")
			return 1
		}
	}
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tCloseable from "@std/core.ms",
// expect-formatted: \tWriteStream, stderr, stdout from "@std/io/io.ms",
// expect-formatted: \texpect_equal, fail from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: type Resource {
// expect-formatted: \tlabel String
// expect-formatted: \toutput WriteStream[String]
// expect-formatted: \tdone Bool = false
// expect-formatted: }
// expect-formatted:
// expect-formatted: // Idempotent, as the Closeable contract requires: the block that ends early closes by
// expect-formatted: // hand and the scope closes again.
// expect-formatted: fn move Resource.close() Void! {
// expect-formatted: \tif self.done { return ok() }
// expect-formatted:
// expect-formatted: \tself.done = true
// expect-formatted: \tvoid self.output.write(value: f"close {self.label}\\n")
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Pair {
// expect-formatted: \tfirst, second Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn report(var output WriteStream[String], label String, value Int) Int {
// expect-formatted: \tvoid output.write(value: f"{label}\\n")
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn combine(first, second Int) Int {
// expect-formatted: \treturn first + second
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn select(var output WriteStream[String]) fn(Int, Int) Int {
// expect-formatted: \tvoid output.write(value: "callable\\n")
// expect-formatted: \treturn combine
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn early(var output WriteStream[String]) Int {
// expect-formatted: \t_outer := Resource(label: "outer", output: stdout())
// expect-formatted: \t_inner := Resource(label: "inner", output: stdout())
// expect-formatted: \treturn report(output: output, label: "return value", value: 5)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn failure() Int! {
// expect-formatted: \treturn error(Error("expected"))
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn propagate(move output WriteStream[String]) Int! {
// expect-formatted: \t_resource := Resource(label: "propagation", output: output)
// expect-formatted: \tnumber := failure()?
// expect-formatted: \treturn ok(number)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn iterable(var output WriteStream[String]) List[Int] {
// expect-formatted: \tvoid output.write(value: "iterable\\n")
// expect-formatted: \treturn [1, 2]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn exercise() Int! {
// expect-formatted: \tvar chosen = stdout()
// expect-formatted: \tvar second_out = stdout()
// expect-formatted: \tvar first_out = stdout()
// expect-formatted: \ttotal := select(output: chosen)(
// expect-formatted: \t\treport(output: second_out, label: "second", value: 2),
// expect-formatted: \t\treport(output: first_out, label: "first", value: 1),
// expect-formatted: \t)
// expect-formatted: \ttotal | expect_equal(3)?
// expect-formatted:
// expect-formatted: \tvar pair_second_out = stdout()
// expect-formatted: \tvar pair_first_out = stdout()
// expect-formatted: \tpair := Pair(
// expect-formatted: \t\tsecond: report(output: pair_second_out, label: "pair second", value: 2),
// expect-formatted: \t\tfirst: report(output: pair_first_out, label: "pair first", value: 1),
// expect-formatted: \t)
// expect-formatted: \t(pair.first + pair.second) | expect_equal(3)?
// expect-formatted:
// expect-formatted: \tvar _resource = Resource(label: "normal", output: stdout())
// expect-formatted: \t_completed := void
// expect-formatted: \t_resource.close()?
// expect-formatted: \tvoid stdout().write(value: "after normal\\n")
// expect-formatted:
// expect-formatted: \tvar count = 0
// expect-formatted:
// expect-formatted: \twhile count < 2 {
// expect-formatted: \t\t_resource := Resource(label: "iteration", output: stdout())
// expect-formatted: \t\tcount += 1
// expect-formatted: \t\tcontinue
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar iterable_out = stdout()
// expect-formatted:
// expect-formatted: \tfor value in iterable(output: iterable_out) {
// expect-formatted: \t\t_resource := Resource(label: "break", output: stdout())
// expect-formatted: \t\tbreak
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch propagate(output: stdout()) {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\tfail(message: "Unexpected case")?
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\t_completed := void
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar early_out = stdout()
// expect-formatted: \tearly(output: early_out) | expect_equal(5)?
// expect-formatted: \tvoid stdout().write(value: "finished\\n")
// expect-formatted: \treturn ok(0)
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \tmatch exercise() {
// expect-formatted: \t\tok(status) => return status
// expect-formatted: \t\terror(cause) => {
// expect-formatted: \t\t\t_written := stderr().write(f"{cause.message}\\n")
// expect-formatted: \t\t\treturn 1
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
