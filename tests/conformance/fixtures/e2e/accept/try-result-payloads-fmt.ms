# conform: tags=closures,control-flow,faults,formatter,generics,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/try-result-payloads.ms
import {expect_equal, expect_true} from "@std/testing.ms"
import TextError from "@std/errors.ms"
import Closeable from "@std/cleanup.ms"

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail

fn relay[T, E: Error](result: Result[T, E], visits: List[Int]) Result[T, E]:
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
    let visits: List[Int] = []
    relay(Result[Int, TextError].error(TextError("")), visits).is_error() | try expect_true
    visits.length() | try expect_equal(expected: 0)
    relay(Result[Int, TextError].ok(0), visits).get() | try expect_equal(expected: 0)
    visits.length() | try expect_equal(expected: 1)

test "try can change the success type":
    (
        text(Result[Int, TextError].error(TextError("failed")))
        .err()
        .text | try expect_equal(expected: "failed")
    )
    text(Result[Int, TextError].ok(42)).get() | try expect_equal(expected: "42")

test "try retains aliases and error views":
    let visits: List[Int] = []
    let original = Failure("before")
    let exact = relay(Result[Int, Failure].error(original), visits)
    let abstract = widened(Result[Int, Failure].error(original))
    original.detail = "after"
    exact.err().detail | try expect_equal(expected: "after")
    abstract.err().message() | try expect_equal(expected: "after")
    widened(Result[Int, Failure].ok(7)).get() | try expect_equal(expected: 7)

fn visit[T, E: Error](result: Result[T, E], visits: List[Int]) Result[T, E]:
    visits.append(1)
    return result

fn tail[T, E: Error](result: Result[T, E], visits: List[Int]) Result[T, E]:
    let value = try visit(result, visits)
    return ok(value)

type TailCleanup:
    visits: List[Int]

impl Closeable for TailCleanup:
    fn close() Unit:
        self.visits.append(2)

fn tail_cleanup(
    result: Result[Int, TextError],
    visits: List[Int]
) Result[Int, TextError]:
    with resource = TailCleanup(visits):
        let value = try visit(result, visits)
        return ok(value)

fn function_tail(result: Result[fn() Int, TextError]) Result[fn() Int, TextError]:
    let value = try result
    return ok(value)

test "tail Results evaluate once and retain payload identity":
    let visits: List[Int] = []
    let original = Failure("before")
    let exact = tail(Result[Int, Failure].error(original), visits)
    original.detail = "after"
    exact.err().detail | try expect_equal(expected: "after")
    tail(Result[Int, TextError].ok(42), visits).get() | try expect_equal(expected: 42)
    tail(Result[Int, TextError].error(TextError("")), visits).is_error() | try expect_true
    visits | try expect_equal(expected: [1, 1, 1])

test "tail Results preserve cleanup on success and failure":
    let visits: List[Int] = []
    tail_cleanup(Result[Int, TextError].ok(42), visits).get() | try expect_equal(
        expected: 42
    )
    visits | try expect_equal(expected: [1, 2])
    tail_cleanup(Result[Int, TextError].error(TextError("")), visits).is_error() | try expect_true
    visits | try expect_equal(expected: [1, 2, 1, 2])

test "function Result payloads keep their calling convention":
    let original = fn() Int: 42
    let result = function_tail(Result[fn() Int, TextError].ok(original))
    let value = result.get()
    value() | try expect_equal(expected: 42)
