# conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,records,stdlib-cleanup,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/try-result-payloads.ms
import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import TextError from "@std/core.ms"
import Closeable from "@std/core.ms"
import filesystem from "@std/fs.ms"

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail

fn relay[T, E: Error](result: Result[T, E], var visits: List[Int]) Result[T, E]:
    let value = try result
    visits.append(1)
    return ok(value)

fn text(result: Result[Int, TextError]) Result[String, TextError]:
    let value = try result
    return ok(value.to_string())

fn widened(result: Result[Int, Failure]) Result[Int, Error]:
    let value = try result
    return ok(value)

test "try preserves empty errors and skips success effects":
    var visits: List[Int] = []
    relay(Result[Int, TextError].error(TextError("")), var visits).is_error() | try expect_true
    visits.length() | try expect_equal(expected: 0)
    relay(Result[Int, TextError].ok(0), var visits).get() | try expect_equal(
        expected: 0
    )
    visits.length() | try expect_equal(expected: 1)

test "try can change the success type":
    (
        text(Result[Int, TextError].error(TextError("failed")))
        .err()
        .text | try expect_equal(expected: "failed")
    )
    text(Result[Int, TextError].ok(42)).get() | try expect_equal(expected: "42")

test "try retains aliases and error views":
    var visits: List[Int] = []
    let original = Failure("before")
    let exact = relay(Result[Int, Failure].error(original.clone()), var visits)
    let abstract = widened(Result[Int, Failure].error(original))
    exact.err().detail | try expect_equal(expected: "before")
    abstract.err().message() | try expect_equal(expected: "before")
    widened(Result[Int, Failure].ok(7)).get() | try expect_equal(expected: 7)

fn visit[T, E: Error](result: Result[T, E], var visits: List[Int]) Result[T, E]:
    visits.append(1)
    return result

fn tail[T, E: Error](result: Result[T, E], var visits: List[Int]) Result[T, E]:
    let value = try visit(result, var visits)
    return ok(value)

type TailCleanup:
    marker: String

# Cleanup runs on a moved copy, so the marker file is the only way to observe it.
impl Closeable for TailCleanup:
    var fn close() Unit:
        let written = filesystem().write_file(self.marker, "closed", true)

fn tail_cleanup(
    result: Result[Int, TextError],
    var visits: List[Int],
    marker: String
) Result[Int, TextError]:
    with resource = TailCleanup(marker):
        let value = try visit(result, var visits)
        return ok(value)

fn function_tail(result: Result[fn() Int, TextError]) Result[fn() Int, TextError]:
    let value = try result
    return ok(value)

test "tail Results evaluate once and retain payload identity":
    var visits: List[Int] = []
    let original = Failure("before")
    let exact = tail(Result[Int, Failure].error(original), var visits)
    exact.err().detail | try expect_equal(expected: "before")
    tail(Result[Int, TextError].ok(42), var visits).get() | try expect_equal(
        expected: 42
    )
    tail(Result[Int, TextError].error(TextError("")), var visits).is_error() | try expect_true
    visits | try expect_equal(expected: [1, 1, 1])

test "tail Results preserve cleanup on success and failure":
    var visits: List[Int] = []
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-tail-") | try expect_ok):
        let first = "{temporary.path()}/first"
        let second = "{temporary.path()}/second"
        tail_cleanup(Result[Int, TextError].ok(42), var visits, first.clone()).get() | try expect_equal(
            expected: 42
        )
        visits | try expect_equal(expected: [1])
        fs.read_file(first).is_ok() | try expect_true
        fs.read_file(second).is_ok() | try expect_false
        tail_cleanup(
            Result[Int, TextError].error(TextError("")), var visits, second.clone()
        ).is_error() | try expect_true
        visits | try expect_equal(expected: [1, 1])
        fs.read_file(second).is_ok() | try expect_true

test "function Result payloads keep their calling convention":
    let original = fn() Int: 42
    let result = function_tail(Result[fn() Int, TextError].ok(original))
    let value = result.get()
    value() | try expect_equal(expected: 42)
