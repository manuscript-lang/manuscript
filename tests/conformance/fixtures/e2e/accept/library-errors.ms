# conform: tags=aliasing,alternatives,control-flow,generics,interfaces,interpolation,lists,match,modules,records,stdlib-encoding,stdlib-fs,stdlib-io,stdlib-json,stdlib-log,stdlib-process,stdlib-testing,strings,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/library-errors.ms
import expect_equal, expect_false, expect_true, fail from "@std/test/test.ms"
import parse, JsonLimits from "@std/data/json.ms"
import hex_decode from "@std/data/encoding.ms"

# Library failures are plain Error values: callers branch on `kind`, not on a domain type.

fn describe_error(cause: Error) String:
    if cause.kind == ErrorCategory.InvalidInput: return "bad limits"
    if cause.kind == ErrorCategory.InvalidData: return "malformed input"
    if cause.kind == ErrorCategory.LimitExceeded: return "bound exceeded"

    return cause.message.clone()

fn decode_generically() Unit!:
    let _bytes = try hex_decode(text: "zz", max_bytes: 10)
    return ok(unit)

fn propagate_generic() Unit!:
    let _completed = try decode_generically()
    return ok(unit)

test "library errors carry a kind callers can branch on":
    let limits = JsonLimits(max_bytes: 100, max_depth: 8, max_values: 32)

    match parse(text: "[", limits: limits):
        ok(_):
            return fail(message: "malformed JSON succeeded")
        error(cause):
            describe_error(cause) | try expect_equal("malformed input")
            cause.message | try expect_equal("JSON: invalid data")

test "propagation with try forwards the same Error":
    let cause = match propagate_generic():
        ok(_):
            return fail(message: "invalid data succeeded")
        error(cause): cause

    cause.kind | try expect_equal(ErrorCategory.InvalidData)
    cause.message | try expect_equal("encoding: invalid data")

test "an Error built by hand has a message, a kind and details":
    let read = Error(
        "read failed", kind: Unavailable,
        details: {"path": "settings.json", "attempt": "2"}
    )
    read.message | try expect_equal("read failed")
    read.kind | try expect_equal(ErrorCategory.Unavailable)
    read.details["path"] | try expect_equal("settings.json")
    read.details["attempt"] | try expect_equal("2")

type ReadError:
    path: String
    attempt: Int
    retryable: Bool

fn failed_read() Unit!ReadError:
    return error(ReadError(path: "settings.json", attempt: 2, retryable: true))

fn propagate_read() Unit!ReadError:
    let _completed = try failed_read()
    return ok(unit)

test "a domain record is still a legal error value":
    let cause = match propagate_read():
        ok(_):
            return fail(message: "failed read succeeded")
        error(cause): cause

    (cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable) | try expect_false

fn read_failure(cause: ReadError) Unit!ReadError:
    return error(cause)

fn general_read(cause: ReadError) Unit!:
    let failed = read_failure(cause)
    if failed.is_error():
        return error(
            Error(
                "read failed", kind: Failed, details: {"path": failed.err().path}
            )
        )

    return ok(unit)

test "a domain record converts to Error by an ordinary function":
    let outcome = general_read(ReadError("a.txt", 1, false))
    outcome.err().kind | try expect_equal(ErrorCategory.Failed)
    outcome.err().details["path"] | try expect_equal("a.txt")
