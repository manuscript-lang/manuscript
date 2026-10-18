import panic from "@std/faults.ms"
import {parse, JsonError, JsonLimits} from "@std/json.ms"
import {EncodingError, hex_decode} from "@std/encoding.ms"

type ApplicationError:
    case Json(cause: JsonError)
    case Encoding(cause: EncodingError)

fn encoding_error(cause: EncodingError) ApplicationError:
    return Encoding(cause)

fn decode_bad_input() Result[Unit, ApplicationError]:
    let decoded = hex_decode("zz", 10)
    if decoded.is_ok():
        return ok(unit)

    return error(encoding_error(decoded.unwrap_error()))

fn json_error_code(cause: JsonError) Int:
    match cause:
        InvalidInput:
            return 1
        InvalidData:
            return 2
        LimitExceeded:
            return 3

test "JSON errors need only JSON cases":
    let limits = JsonLimits(100, 8, 32)
    let parsed = parse("[", limits)
    if parsed.is_ok():
        return panic("malformed JSON succeeded")
    if json_error_code(parsed.unwrap_error()) != 2:
        return panic("wrong JSON cause")

test "explicit error mapping preserves the cause":
    let expected: Result[Unit, ApplicationError] = error(
        Encoding(EncodingError.InvalidData)
    )
    if decode_bad_input() != expected:
        return panic("error mapping lost its cause")

# Error is an ordinary operation contract. Custom errors use ordinary impl blocks.
import IoError from "@std/io.ms"

type CustomError:
    detail: String

impl Error for CustomError:
    fn message() String:
        return self.detail

type TaggedError[T]:
    detail: T

impl Error for TaggedError[T]:
    fn message() String:
        return "tagged failure"

fn decode_generically() Result[Unit, Error]:
    let _bytes = try hex_decode("zz", 10)
    return ok(unit)

fn propagate_generic() Result[Unit, Error]:
    try decode_generically()
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
    if describe_error(json) != "malformed JSON":
        return panic("specific handler did not run")

    let io = Error(IoError.Failed("disk diagnostic"))
    if describe_error(io) != "I/O: disk diagnostic":
        return panic("specific handler lost diagnostic")

    let custom = Error(CustomError("application diagnostic"))
    if describe_error(custom) != "application diagnostic":
        return panic("generic fallback did not use custom implementation")

    let wrapped = Error(json)
    if describe_error(wrapped) != "malformed JSON":
        return panic("repeated views changed concrete identity")

    let propagated = propagate_generic()
    if propagated.is_ok():
        return panic("invalid data succeeded")

    let cause = propagated.unwrap_error()

    match cause:
        EncodingError(encoding):
            if encoding != EncodingError.InvalidData:
                return panic("generic propagation lost original cause")
        _:
            return panic("generic propagation lost concrete type")

test "type patterns compare exact generic applications":
    let integer = Error(TaggedError(7))
    let text = Error(TaggedError("text diagnostic"))
    if (
        tagged_detail(integer) != "integer 7"
        or tagged_detail(text) != "text diagnostic"
    ):
        return panic("type pattern ignored generic arguments")
    if not generic_type_pattern(integer, 1):
        return panic("generic type pattern did not resolve its argument")
    if generic_type_pattern(integer, "different type"):
        return panic("generic type pattern matched wrong application")

test "Error views can be stored and matched":
    let shared = Error(CustomError("shared diagnostic"))
    let errors: List[Error] = [shared]
    let first = errors.at(0)
    if first.is_none():
        return panic("shared errors collection was empty")

    match first.unwrap():
        CustomError(custom):
            if custom.detail != "shared diagnostic":
                return panic("shared view lost receiver")
        _:
            return panic("shared view lost type")

type ReadError:
    diagnostic: String
    path: String
    attempt: Int
    retryable: Bool

impl Error for ReadError:
    fn message() String:
        return self.diagnostic

fn failed_read() Result[Unit, ReadError]:
    return error(ReadError("read failed", "settings.json", 2, retryable: true))

fn propagate_read() Result[Unit, ReadError]:
    try failed_read()
    return ok(unit)

test "domain error fields survive propagation without a wrapper":
    let propagated = propagate_read()
    if propagated.is_ok():
        return panic("failed read succeeded")

    let cause = propagated.unwrap_error()
    if (cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable):
        return panic("lost typed error fields")

    let message = cause.message
    if cause.message() != "read failed" or message() != "read failed":
        return panic("lost diagnostic")

    let generic: Error = cause

    match generic:
        ReadError(read):
            if (read.path != "settings.json" or read.attempt != 2 or not read.retryable):
                return panic("generic boundary lost typed fields")
        _:
            return panic("generic boundary lost concrete error")

fn read_failure(cause: ReadError) Result[Unit, ReadError]:
    return error(cause)

fn general_read(cause: ReadError) Result[Unit, Error]:
    try read_failure(cause)
    return ok(unit)

fn forward_read(cause: ReadError) Result[Unit, Error]:
    return read_failure(cause)

fn generic_failure[E: Error](cause: E) Result[Unit, E]:
    return error(cause)

fn generic_propagation[E: Error](cause: E) Result[Unit, Error]:
    try generic_failure(cause)
    return ok(unit)

fn describe_direct(cause: Error) String:
    return cause.message()

test "specific errors pass directly into Error boundaries":
    let original = ReadError("read failed", "settings.json", 2, retryable: true)
    let shared: Error = original
    if describe_direct(original) != "read failed" or shared.message() != "read failed":
        return panic("direct Error boundary lost diagnostic")

    let results: List[Result[Unit, Error]] = [
        general_read(original),
        forward_read(original),
        generic_propagation(original),
        error(original)
    ]
    original.attempt = 3

    for result in results:
        if result.is_ok():
            return panic("failed read succeeded")

        let cause = result.unwrap_error()

        match cause:
            ReadError(read):
                if (
                    read.path != "settings.json"
                    or read.attempt != 3
                    or not read.retryable
                ):
                    return panic("Error boundary copied or lost typed fields")

                read.path = "changed.json"
                read.path = "settings.json"
            _:
                return panic("Error boundary lost original type")

    match shared:
        ReadError(read):
            read.path = "changed.json"
        _:
            return panic("shared Error lost concrete type")

    if original.path != "changed.json":
        return panic("Error boundary copied original error")

fn read_success() Result[Int, ReadError]:
    return ok(7)

fn general_read_success() Result[Int, Error]:
    return read_success()

test "Error Result forwarding preserves successful payloads":
    if let value = general_read_success():
        if value != 7:
            return panic("Error Result changed success")
    else:
        return panic("Error Result turned success into failure")

type ValidationError:
    case InvalidField(field: String, expected: Int, actual: Int)

fn invalid_field() Result[Unit, ValidationError]:
    return error(InvalidField(field: "attempt", expected: 1, actual: 0))

test "domain case payloads need no Error implementation":
    let invalid = invalid_field()
    if invalid.is_ok():
        return panic("invalid field succeeded")

    let cause = invalid.unwrap_error()

    match cause:
        InvalidField(field, expected, actual):
            if (field != "attempt" or expected != 1 or actual != 0):
                return panic("domain case lost typed fields")

test "standard error diagnostics work directly":
    let cause = IoError.Failed("read failed")
    let message = cause.message
    if cause.message() != "read failed" or message() != "read failed":
        return panic("standard diagnostic lost")
    if JsonError.InvalidData.message() != "JSON: invalid data":
        return panic("nullary standard diagnostic lost")

import FileSystemError from "@std/fs.ms"
import {LogError} from "@std/log.ms"
import {CommandError} from "@std/process.ms"
import {ExecutionError, StartError} from "@std/tasks.ms"

test "standard diagnostics preserve messages and wrapped causes":
    let sink = LogError.Io(IoError.Failed("sink diagnostic"))
    if Error(sink).message() != "sink diagnostic":
        return panic("log error lost underlying diagnostic")

    let file_sink = LogError.FileSystem(FileSystemError.Failed("file sink diagnostic"))
    if Error(file_sink).message() != "file sink diagnostic":
        return panic("log file error lost underlying diagnostic")
    if (
        Error(
            CommandError.Failed("command diagnostic")
        ).message() != "command diagnostic"
    ):
        return panic("command error lost diagnostic")
    if (
        Error(
            ExecutionError.Timeout
        ).message() != "task execution: operation timed out"
    ):
        return panic("execution error has no diagnostic")
    if Error(StartError.Full).message() != "scheduler: capacity exhausted":
        return panic("start error has no diagnostic")

# The type-pattern rule also works for unrelated operation contracts.
interface Label[T]:
    fn label() T

type Labelled[T]:
    value: T

impl Label[T] for Labelled[T]:
    fn label() T:
        return self.value

fn match_label(view: Label[String]) String:
    match view:
        Labelled[String](receiver):
            return receiver.value
        _:
            return view.label()

import Synchronized from "@std/sync.ms"

fn counted_view(count: Synchronized[Int]) Label[String]:
    with locked = count.lock():
        locked.set(locked.get() + 1)
    return Label[String](Labelled("label diagnostic"))

test "contract matches evaluate once and preserve ordinary contract semantics":
    let count = Synchronized(0)

    match counted_view(count):
        Labelled[String](receiver):
            if receiver.value != "label diagnostic":
                return panic("unrelated contract pattern lost receiver")
        _:
            return panic("unrelated contract pattern did not run")

    with locked = count.lock():
        if locked.get() != 1:
            return panic("contract scrutinee was evaluated more than once")
    let view = Label[String](Labelled("separate handler"))
    if match_label(view) != "separate handler":
        return panic("contract match depended on Error identity")

import filesystem from "@std/fs.ms"

fn check_missing_file() Result[Unit, FileSystemError]:
    let fs = filesystem()
    let directory = try fs.temporary_directory("manuscript-errors-")
    let missing = "{directory}/missing-secret-token"
    let read = fs.read_file(missing)
    if read.is_ok():
        return panic("missing file read succeeded")

    let cause = read.unwrap_error()

    match cause:
        NotFound:
            let diagnostic = cause.message
            let shared: Error = cause
            if (
                diagnostic() != "filesystem: file or directory not found"
                or shared.message() != diagnostic()
            ):
                return panic("missing file diagnostic lost")
        _:
            return panic("missing file changed error case")

    let stat = fs.stat(missing, follow_links: true)
    if stat.is_ok():
        return panic("missing file stat succeeded")
    if stat.unwrap_error().message() != "filesystem: file or directory not found":
        return panic("stat diagnostic lost")

    try fs.remove(directory, recursive: false)
    return ok(unit)

test "missing file diagnostics preserve the filesystem case":
    try check_missing_file()
