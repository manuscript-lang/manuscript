import {expect_equal, expect_true} from "@std/testing.ms"
import TextError from "@std/errors.ms"

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
