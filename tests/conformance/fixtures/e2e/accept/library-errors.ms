# conform: tags=aliasing,alternatives,control-flow,generics,interfaces,interpolation,lists,match,modules,records,stdlib-encoding,stdlib-fs,stdlib-io,stdlib-json,stdlib-log,stdlib-process,stdlib-testing,strings,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/library-errors.ms
import expect_equal, expect_false, expect_true, fail from "@std/test.ms"
import parse, JsonError, JsonLimits from "@std/json.ms"
import EncodingError, hex_decode from "@std/encoding.ms"

type ApplicationError:
    case Json(cause: JsonError)
    case Encoding(cause: EncodingError)

impl Error for ApplicationError:
    fn message() String: "ApplicationError"

fn encoding_error(cause: EncodingError) ApplicationError:
    return Encoding(cause)

fn decode_bad_input() Unit!ApplicationError:
    match hex_decode(text: "zz", max_bytes: 10):
        ok(_):
            return ok(unit)
        error(cause):
            return error(encoding_error(cause))

fn json_error_code(cause: JsonError) Int:
    match cause:
        InvalidInput:
            return 1
        InvalidData:
            return 2
        LimitExceeded:
            return 3

test "JSON errors need only JSON cases":
    let limits = JsonLimits(max_bytes: 100, max_depth: 8, max_values: 32)

    match parse(text: "[", limits: limits):
        ok(_):
            return fail(message: "malformed JSON succeeded")
        error(cause):
            try expect_equal(json_error_code(cause), 2)

test "explicit error mapping preserves the cause":
    let expected: Unit!ApplicationError = error(
        Encoding(EncodingError.InvalidData)
    )
    decode_bad_input() | try expect_equal(expected)

# Error is an ordinary operation contract. Custom errors use ordinary impl blocks.
import IoError from "@std/io.ms"

type CustomError:
    detail: String

impl Error for CustomError:
    fn message() String:
        return self.detail.clone()

type TaggedError[T]:
    detail: T

impl Error for TaggedError[T]:
    fn message() String:
        return "tagged failure"

fn decode_generically() Unit!:
    let bytes = try hex_decode(text: "zz", max_bytes: 10)
    return ok(unit)

fn propagate_generic() Unit!:
    let completed = try decode_generically()
    return ok(unit)

fn describe_error(cause: Error) String:
    match cause:
        JsonError(json): return describe_json_error(json)
        IoError(io): return describe_io_error(io)
        _:
            return cause.message()

fn describe_json_error(cause: JsonError) String:
    match cause:
        InvalidInput: return "bad JSON limits"
        InvalidData: return "malformed JSON"
        LimitExceeded: return "JSON bound exceeded"

fn describe_io_error(cause: IoError) String:
    match cause:
        Failed(message): return "I/O: {message}"
        _: return cause.message()

fn tagged_detail(cause: Error) String:
    match cause:
        TaggedError[Int](item):
            return "integer {item.detail}"
        TaggedError[String](item):
            return item.detail
        _:
            return cause.message()

fn generic_type_pattern[T](cause: Error, expected: T) Bool:
    match cause:
        TaggedError[T](_):
            return true
        _:
            return false

test "generic handling preserves the concrete error and its payload":
    let json = Error(JsonError.InvalidData)
    describe_error(json) | try expect_equal("malformed JSON")

    let io = Error(IoError.Failed("disk diagnostic"))
    describe_error(io) | try expect_equal("I/O: disk diagnostic")

    let custom = Error(CustomError("application diagnostic"))
    describe_error(custom) | try expect_equal("application diagnostic")

    let wrapped = Error(json)
    describe_error(wrapped) | try expect_equal("malformed JSON")

    let cause = match propagate_generic():
        ok(_):
            return fail(message: "invalid data succeeded")
        error(cause): cause

    match cause:
        EncodingError(encoding):
            try expect_equal(encoding, EncodingError.InvalidData)
        _:
            return fail(message: "generic propagation lost concrete type")

test "type patterns compare exact generic applications":
    let integer = Error(TaggedError(7))
    let text = Error(TaggedError("text diagnostic"))
    (
        (
            tagged_detail(Error(TaggedError(7))) != "integer 7"
            or tagged_detail(text) != "text diagnostic"
        )
    ) | try expect_false
    (generic_type_pattern(cause: Error(TaggedError(7)), expected: 1)) | try expect_true
    generic_type_pattern(cause: integer, expected: "different type") | try expect_false

test "Error views can be stored and matched":
    let shared = Error(CustomError("shared diagnostic"))
    let errors: List[Error] = [shared]
    let cause = errors[0]

    match cause:
        CustomError(custom):
            try expect_equal(custom.detail, "shared diagnostic")
        _:
            return fail(message: "shared view lost type")

type ReadError:
    diagnostic: String
    path: String
    attempt: Int
    retryable: Bool

impl Error for ReadError:
    fn message() String:
        return self.diagnostic.clone()

fn failed_read() Unit!ReadError:
    return error(
        ReadError(
            diagnostic: "read failed", path: "settings.json", attempt: 2,
            retryable: true
        )
    )

fn propagate_read() Unit!ReadError:
    let completed = try failed_read()
    return ok(unit)

test "domain error fields survive propagation without a wrapper":
    let cause = match propagate_read():
        ok(_):
            return fail(message: "failed read succeeded")
        error(cause): cause

    (cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable) | try expect_false

    let message = cause.message
    (cause.message() != "read failed" or message() != "read failed") | try expect_false

    let generic: Error = cause

    match generic:
        ReadError(read):
            (
                (
                    (
                        read.path != "settings.json"
                        or read.attempt != 2
                        or not read.retryable
                    )
                ) | try expect_false
            )
        _:
            return fail(message: "generic boundary lost concrete error")

fn read_failure(cause: ReadError) Unit!ReadError:
    return error(cause)

fn general_read(cause: ReadError) Unit!:
    let completed = try read_failure(cause)
    return ok(unit)

fn forward_read(cause: ReadError) Unit!:
    return read_failure(cause)

fn generic_failure[E: Error](cause: E) Unit!E:
    return error(cause)

fn generic_propagation[E: Error](cause: E) Unit!:
    let completed = try generic_failure(cause)
    return ok(unit)

fn describe_direct(cause: Error) String:
    return cause.message()

test "specific errors pass directly into Error boundaries":
    let original = ReadError(
        diagnostic: "read failed", path: "settings.json", attempt: 3, retryable: true
    )
    let shared: Error = Error(original.clone())
    (
        describe_direct(
            original.clone()
        ) != "read failed" or shared.message() != "read failed"
    ) | try expect_false

    let results: List[Unit!] = [
        general_read(original.clone()), forward_read(original.clone()),
        generic_propagation(original.clone()), error(original.clone())
    ]

    for result in results:
        let cause = match result:
            ok(_):
                return fail(message: "failed read succeeded")
            error(cause): cause

        match cause:
            ReadError(read):
                (
                    (
                        read.path != "settings.json"
                        or read.attempt != 3
                        or not read.retryable
                    )
                ) | try expect_false
            _:
                return fail(message: "Error boundary lost original type")

    match shared:
        ReadError(read):
            read.path | try expect_equal("settings.json")
        _:
            return fail(message: "shared Error lost concrete type")

    original.path | try expect_equal("settings.json")

fn read_success() Int!ReadError:
    return ok(7)

fn general_read_success() Int!:
    return read_success()

test "Error Result forwarding preserves successful payloads":
    match general_read_success():
        ok(value):
            try expect_equal(value, 7)
        error(_):
            return fail(message: "Error Result turned success into failure")

type ValidationError:
    case InvalidField(field: String, expected: Int, actual: Int)

impl Error for ValidationError:
    fn message() String: "ValidationError"

fn invalid_field() Unit!ValidationError:
    return error(InvalidField(field: "attempt", expected: 1, actual: 0))

test "domain case payloads need no Error implementation":
    let cause = match invalid_field():
        ok(_):
            return fail(message: "invalid field succeeded")
        error(cause): cause

    match cause:
        InvalidField(field, expected, actual):
            ((field != "attempt" or expected != 1 or actual != 0) | try expect_false)

test "standard error diagnostics work directly":
    let cause = IoError.Failed("read failed")
    let message = cause.message
    (cause.message() != "read failed" or message() != "read failed") | try expect_false
    JsonError.InvalidData.message() | try expect_equal("JSON: invalid data")

import FileSystemError from "@std/fs.ms"
import LogError from "@std/log.ms"
import CommandError from "@std/process.ms"

test "standard diagnostics preserve messages and wrapped causes":
    let sink = LogError.Io(IoError.Failed("sink diagnostic"))
    Error(sink).message() | try expect_equal("sink diagnostic")

    let file_sink = LogError.FileSystem(FileSystemError.Failed("file sink diagnostic"))
    Error(file_sink).message() | try expect_equal("file sink diagnostic")
    (
        (
            Error(
                CommandError.Failed("command diagnostic")
            ).message() != "command diagnostic"
        )
    ) | try expect_false

# The type-pattern rule also works for unrelated operation contracts.
interface Label[T]:
    fn label() T

type Labelled[T]:
    value: T

impl Label[String] for Labelled[String]:
    fn label() String:
        return self.value

fn match_label(view: Label[String]) String:
    match view:
        Labelled[String](receiver):
            return receiver.value
        _:
            return view.label().clone()

type Count:
    value: Int

fn counted_view(var count: Count) Label[String]:
    count.value = count.value + 1
    return Label[String](Labelled("label diagnostic"))

test "contract matches evaluate once and preserve ordinary contract semantics":
    var count = Count(value: 0)

    match counted_view(var count):
        Labelled[String](receiver):
            try expect_equal(receiver.value, "label diagnostic")
        _:
            return fail(message: "unrelated contract pattern did not run")

    count.value | try expect_equal(1)

    let view = Label[String](Labelled("separate handler"))
    match_label(view) | try expect_equal("separate handler")

import read_file, remove, stat, temporary_directory from "@std/fs.ms"

fn check_missing_file() Unit!:
    let directory = try temporary_directory("manuscript-errors-")
    let missing = "{directory}/missing-secret-token"

    let cause = match read_file(path: missing):
        ok(_):
            return fail(message: "missing file read succeeded")
        error(cause): cause

    match cause:
        NotFound:
            let diagnostic = cause.message
            let shared: Error = cause
            (
                (
                    (
                        diagnostic() != "filesystem: file or directory not found"
                        or shared.message() != diagnostic()
                    )
                ) | try expect_false
            )
        _:
            return fail(message: "missing file changed error case")

    match stat(path: missing, follow_links: true):
        ok(_):
            return fail(message: "missing file stat succeeded")
        error(stat_cause):
            try expect_equal(
                stat_cause.message(), "filesystem: file or directory not found"
            )

    let removed = try remove(path: directory, recursive: false)
    return ok(unit)

test "missing file diagnostics preserve the filesystem case":
    match check_missing_file():
        ok(_):
            return unit
        error(cause):
            return fail(message: cause.message())
