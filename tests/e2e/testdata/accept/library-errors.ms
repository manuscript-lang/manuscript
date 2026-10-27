from "@std/test.ms" import expect_equal, expect_false, expect_true, fail
from "@std/json.ms" import parse, JsonError, JsonLimits
from "@std/encoding.ms" import EncodingError, hex_decode

type ApplicationError:
    case Json(cause: JsonError)
    case Encoding(cause: EncodingError)

impl Error for ApplicationError:
    def message() -> String: "ApplicationError"

def encoding_error(cause: EncodingError) -> ApplicationError:
    return Encoding(cause)

def decode_bad_input() -> Result[Unit, ApplicationError]:
    match hex_decode(text: "zz", max_bytes: 10):
        case ok(_):
            return ok(())
        case error(cause):
            return error(encoding_error(cause))

def json_error_code(cause: JsonError) -> Int:
    match cause:
        case InvalidInput:
            return 1
        case InvalidData:
            return 2
        case LimitExceeded:
            return 3

test "JSON errors need only JSON cases":
    let limits = JsonLimits(max_bytes: 100, max_depth: 8, max_values: 32)

    match parse(text: "[", limits: limits):
        case ok(_):
            return fail(message: "malformed JSON succeeded")
        case error(cause):
            try expect_equal(json_error_code(cause), 2)

test "explicit error mapping preserves the cause":
    let expected: Result[Unit, ApplicationError] = error(
        Encoding(EncodingError.InvalidData)
    )
    decode_bad_input() | try expect_equal(expected)

# Error is an ordinary operation contract. Custom errors use ordinary impl blocks.
from "@std/io.ms" import IoError

type CustomError:
    detail: String

impl Error for CustomError:
    def message() -> String:
        return self.detail.clone()

type TaggedError[T]:
    detail: T

impl Error for TaggedError[T]:
    def message() -> String:
        return "tagged failure"

def decode_generically() -> Result[Unit, Error]:
    let bytes = try hex_decode(text: "zz", max_bytes: 10)
    return ok(())

def propagate_generic() -> Result[Unit, Error]:
    let completed = try decode_generically()
    return ok(())

def describe_error(cause: Error) -> String:
    match cause:
        case JsonError(json): return describe_json_error(json)
        case IoError(io): return describe_io_error(io)
        case _:
            return cause.message()

def describe_json_error(cause: JsonError) -> String:
    match cause:
        case InvalidInput: return "bad JSON limits"
        case InvalidData: return "malformed JSON"
        case LimitExceeded: return "JSON bound exceeded"

def describe_io_error(cause: IoError) -> String:
    match cause:
        case Failed(message): return f"I/O: {message}"
        case _: return cause.message()

def tagged_detail(cause: Error) -> String:
    match cause:
        case TaggedError[Int](item):
            return f"integer {item.detail}"
        case TaggedError[String](item):
            return item.detail.clone()
        case _:
            return cause.message()

def generic_type_pattern[T](cause: Error, expected: T) -> Bool:
    match cause:
        case TaggedError[T](_):
            return True
        case _:
            return False

test "generic handling preserves the concrete error and its payload":
    let json: Error = JsonError.InvalidData
    describe_error(json) | try expect_equal("malformed JSON")

    let io: Error = IoError.Failed("disk diagnostic")
    describe_error(io) | try expect_equal("I/O: disk diagnostic")

    let custom: Error = CustomError("application diagnostic")
    describe_error(custom) | try expect_equal("application diagnostic")

    let wrapped: Error = json
    describe_error(wrapped) | try expect_equal("malformed JSON")

    let cause = match propagate_generic():
        case ok(_):
            return fail(message: "invalid data succeeded")
        case error(cause): cause

    match cause:
        case EncodingError(encoding):
            try expect_equal(encoding, EncodingError.InvalidData)
        case _:
            return fail(message: "generic propagation lost concrete type")

test "type patterns compare exact generic applications":
    let integer: Error = TaggedError(7)
    let text: Error = TaggedError("text diagnostic")
    (
        (
            tagged_detail(TaggedError(7)) != "integer 7"
            or tagged_detail(text) != "text diagnostic"
        )
    ) | try expect_false
    (generic_type_pattern(cause: TaggedError(7), expected: 1)) | try expect_true
    generic_type_pattern(cause: integer, expected: "different type") | try expect_false

test "Error views can be stored and matched":
    let shared: Error = CustomError("shared diagnostic")
    let errors: List[Error] = [shared]
    let cause = errors[0]

    match cause:
        case CustomError(custom):
            try expect_equal(custom.detail, "shared diagnostic")
        case _:
            return fail(message: "shared view lost type")

type ReadError:
    diagnostic: String
    path: String
    attempt: Int
    retryable: Bool

impl Error for ReadError:
    def message() -> String:
        return self.diagnostic.clone()

def failed_read() -> Result[Unit, ReadError]:
    return error(
        ReadError(
            diagnostic: "read failed", path: "settings.json", attempt: 2,
            retryable: True
        )
    )

def propagate_read() -> Result[Unit, ReadError]:
    let completed = try failed_read()
    return ok(())

test "domain error fields survive propagation without a wrapper":
    let cause = match propagate_read():
        case ok(_):
            return fail(message: "failed read succeeded")
        case error(cause): cause

    (cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable) | try expect_false

    let message = cause.message
    (cause.message() != "read failed" or message() != "read failed") | try expect_false

    let generic: Error = cause

    match generic:
        case ReadError(read):
            (
                (
                    (
                        read.path != "settings.json"
                        or read.attempt != 2
                        or not read.retryable
                    )
                ) | try expect_false
            )
        case _:
            return fail(message: "generic boundary lost concrete error")

def read_failure(cause: ReadError) -> Result[Unit, ReadError]:
    return error(cause)

def general_read(cause: ReadError) -> Result[Unit, Error]:
    let completed = try read_failure(cause)
    return ok(())

def forward_read(cause: ReadError) -> Result[Unit, Error]:
    return read_failure(cause)

def generic_failure[E: Error](cause: E) -> Result[Unit, E]:
    return error(cause)

def generic_propagation[E: Error](cause: E) -> Result[Unit, Error]:
    let completed = try generic_failure(cause)
    return ok(())

def describe_direct(cause: Error) -> String:
    return cause.message()

test "specific errors pass directly into Error boundaries":
    let original = ReadError(
        diagnostic: "read failed", path: "settings.json", attempt: 3, retryable: True
    )
    let shared: Error = original.clone()
    (
        describe_direct(
            original.clone()
        ) != "read failed" or shared.message() != "read failed"
    ) | try expect_false

    let results: List[Result[Unit, Error]] = [
        general_read(original.clone()), forward_read(original.clone()),
        generic_propagation(original.clone()), error(original.clone())
    ]

    for result in results:
        let cause = match result:
            case ok(_):
                return fail(message: "failed read succeeded")
            case error(cause): cause

        match cause:
            case ReadError(read):
                (
                    (
                        read.path != "settings.json"
                        or read.attempt != 3
                        or not read.retryable
                    )
                ) | try expect_false
            case _:
                return fail(message: "Error boundary lost original type")

    match shared:
        case ReadError(read):
            read.path | try expect_equal("settings.json")
        case _:
            return fail(message: "shared Error lost concrete type")

    original.path | try expect_equal("settings.json")

def read_success() -> Result[Int, ReadError]:
    return ok(7)

def general_read_success() -> Result[Int, Error]:
    return read_success()

test "Error Result forwarding preserves successful payloads":
    match general_read_success():
        case ok(value):
            try expect_equal(value, 7)
        case error(_):
            return fail(message: "Error Result turned success into failure")

type ValidationError:
    case InvalidField(field: String, expected: Int, actual: Int)

impl Error for ValidationError:
    def message() -> String: "ValidationError"

def invalid_field() -> Result[Unit, ValidationError]:
    return error(InvalidField(field: "attempt", expected: 1, actual: 0))

test "domain case payloads need no Error implementation":
    let cause = match invalid_field():
        case ok(_):
            return fail(message: "invalid field succeeded")
        case error(cause): cause

    match cause:
        case InvalidField(field, expected, actual):
            ((field != "attempt" or expected != 1 or actual != 0) | try expect_false)

test "standard error diagnostics work directly":
    let cause = IoError.Failed("read failed")
    let message = cause.message
    (cause.message() != "read failed" or message() != "read failed") | try expect_false
    JsonError.InvalidData.message() | try expect_equal("JSON: invalid data")

from "@std/fs.ms" import FileSystemError
from "@std/log.ms" import LogError
from "@std/process.ms" import CommandError

test "standard diagnostics preserve messages and wrapped causes":
    let sink = LogError.Io(IoError.Failed("sink diagnostic"))
    sink.message() | try expect_equal("sink diagnostic")

    let file_sink = LogError.FileSystem(FileSystemError.Failed("file sink diagnostic"))
    file_sink.message() | try expect_equal("file sink diagnostic")
    ((CommandError.Failed("command diagnostic").message() != "command diagnostic")) | try expect_false

# The type-pattern rule also works for unrelated operation contracts.
interface Label[T]:
    def label() -> ref T

type Labelled[T]:
    value: T

impl Label[String] for Labelled[String]:
    def label() -> ref String:
        return self.value

def match_label(view: Label[String]) -> String:
    match view:
        case Labelled[String](receiver):
            return receiver.value.clone()
        case _:
            return view.label().clone()

type Count:
    value: Int

def counted_view(var count: Count) -> Label[String]:
    count.value = count.value + 1
    return Labelled("label diagnostic")

test "contract matches evaluate once and preserve ordinary contract semantics":
    var count = Count(value: 0)

    match counted_view(var count):
        case Labelled[String](receiver):
            try expect_equal(receiver.value, "label diagnostic")
        case _:
            return fail(message: "unrelated contract pattern did not run")

    count.value | try expect_equal(1)

    let view: Label[String] = Labelled("separate handler")
    match_label(view) | try expect_equal("separate handler")

from "@std/fs.ms" import filesystem

def check_missing_file() -> Result[Unit, Error]:
    let fs = filesystem()
    let directory = try fs.temporary_directory("manuscript-errors-")
    let missing = f"{directory}/missing-secret-token"

    let cause = match fs.read_file(path: missing):
        case ok(_):
            return fail(message: "missing file read succeeded")
        case error(cause): cause

    match cause:
        case NotFound:
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
        case _:
            return fail(message: "missing file changed error case")

    match fs.stat(path: missing, follow_links: True):
        case ok(_):
            return fail(message: "missing file stat succeeded")
        case error(stat_cause):
            try expect_equal(
                stat_cause.message(), "filesystem: file or directory not found"
            )

    let removed = try fs.remove(path: directory, recursive: False)
    return ok(())

test "missing file diagnostics preserve the filesystem case":
    match check_missing_file():
        case ok(_):
            return ()
        case error(cause):
            return fail(message: cause.message())
