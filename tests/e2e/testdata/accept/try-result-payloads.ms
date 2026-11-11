import (
	Closeable from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms",
)

type Failure:
	detail: String

fn relay[T, E](result: T!E, var visits: List[Int]) T!E:
	value := result?
	visits.append(1)
	return ok(value)

fn text(result: Int!Error) String!Error:
	value := result?
	return ok(value.to_string())

test "try preserves empty errors and skips success effects":
	var visits: List[Int] = []
	relay(Result[Int, Error].error(Error("")), var visits).is_error() | expect_true?
	visits.length() | expect_equal(0)?
	relay(Result[Int, Error].ok(0), var visits).get() | expect_equal(0)?
	visits.length() | expect_equal(1)?

test "try can change the success type":
	text(Result[Int, Error].error(Error("failed"))).err().message | expect_equal(
		"failed"
	)?
	text(Result[Int, Error].ok(42)).get() | expect_equal("42")?

test "try retains aliases and error views":
	var visits: List[Int] = []
	original := Failure("before")
	exact := relay(Result[Int, Failure].error(original.clone()), var visits)
	exact.err().detail | expect_equal("before")?

fn visit[T, E](result: T!E, var visits: List[Int]) T!E:
	visits.append(1)
	return result

fn tail[T, E](result: T!E, var visits: List[Int]) T!E:
	value := visit(result, var visits)?
	return ok(value)

type TailCleanup:
	marker: String

// Cleanup runs on a moved copy, so the marker file is the only way to observe it.
impl Closeable for TailCleanup:
	var fn close() Unit!:
		_written := write_file(self.marker, "closed", true).wait()

fn tail_cleanup(result: Int!Error, var visits: List[Int], marker: String) Int!Error:
	_resource := TailCleanup(marker)
	value := visit(result, var visits)?
	return ok(value)

fn function_tail(result: (fn() Int)!Error) (fn() Int)!Error:
	value := result?
	return ok(value)

test "tail Results evaluate once and retain payload identity":
	var visits: List[Int] = []
	original := Failure("before")
	exact := tail(Result[Int, Failure].error(original), var visits)
	exact.err().detail | expect_equal("before")?
	tail(Result[Int, Error].ok(42), var visits).get() | expect_equal(42)?
	tail(Result[Int, Error].error(Error("")), var visits).is_error() | expect_true?
	visits | expect_equal([1, 1, 1])?

test "tail Results preserve cleanup on success and failure":
	var visits: List[Int] = []
	temporary := temporary("manuscript-tail-") | expect_ok?
	first := "{temporary.path()}/first"
	second := "{temporary.path()}/second"
	tail_cleanup(Result[Int, Error].ok(42), var visits, first.clone()).get() | expect_equal(
		42
	)?
	visits | expect_equal([1])?
	read_file(first).wait().is_ok() | expect_true?
	read_file(second).wait().is_ok() | expect_false?
	tail_cleanup(Result[Int, Error].error(Error("")), var visits, second.clone()).is_error() | expect_true?
	visits | expect_equal([1, 1])?
	read_file(second).wait().is_ok() | expect_true?

test "function Result payloads keep their calling convention":
	original := fn() Int: 42
	wrapped := Result[fn() Int, Error].ok(original)
	value := function_tail(wrapped)?
	value() | expect_equal(42)?
