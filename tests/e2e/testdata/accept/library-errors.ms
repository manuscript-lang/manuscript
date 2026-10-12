import panic from "@std/faults.ms"
import Result from "@std/result.ms"
import {parse, JsonError, JsonLimits} from "@std/json.ms"
import {EncodingError, hex_decode} from "@std/encoding.ms"

type ApplicationError:
    case Json(cause: JsonError)
    case Encoding(cause: EncodingError)

fn encoding_error(cause: EncodingError) -> ApplicationError:
    return Encoding(cause: cause)

fn decode_bad_input() -> Result[Unit, ApplicationError]:
    match hex_decode(text: "zz", max_bytes: 10):
        ok(_):
            return ok(value: unit)
        error(cause):
            return error(cause: encoding_error(cause))

fn json_error_code(cause: JsonError) -> Int:
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
            return panic(message: "malformed JSON succeeded")
        error(cause):
            if json_error_code(cause) != 2:
                return panic(message: "wrong JSON cause")

test "explicit error mapping preserves the cause":
    let expected: Result[Unit, ApplicationError] = error(cause: Encoding(cause: EncodingError.InvalidData))
    if decode_bad_input() != expected:
        return panic(message: "error mapping lost its cause")

# Error is an ordinary operation contract. Custom errors use ordinary impl blocks.
import Error from "@std/errors.ms"
import IoError from "@std/io.ms"
import List from "@std/collections.ms"

type CustomError:
    detail: String

impl Error for CustomError:
    fn message() -> String:
        return self.detail

type TaggedError[T]:
    detail: T

impl Error for TaggedError[T]:
    fn message() -> String:
        return "tagged failure"

fn decode_generically() -> Result[Unit, Error]:
    match hex_decode(text: "zz", max_bytes: 10):
        ok(_):
            return ok(value: unit)
        error(cause):
            return error(cause: Error(value: cause))

fn propagate_generic() -> Result[Unit, Error]:
    let completed = try decode_generically()
    return ok(value: unit)

fn describe_error(cause: Error) -> String:
    match cause:
        JsonError(json):
            match json:
                InvalidInput:
                    return "bad JSON limits"
                InvalidData:
                    return "malformed JSON"
                LimitExceeded:
                    return "JSON bound exceeded"
        IoError(io):
            match io:
                Failed(message):
                    return "I/O: {message}"
                _:
                    return io.message()
        _:
            return cause.message()

fn tagged_detail(cause: Error) -> String:
    match cause:
        TaggedError[Int](item):
            return "integer {item.detail}"
        TaggedError[String](item):
            return item.detail
        _:
            return cause.message()

fn generic_type_pattern[T](cause: Error, expected: T) -> Bool:
    match cause:
        TaggedError[T](_):
            return true
        _:
            return false

test "generic handling preserves the concrete error and its payload":
    let json = Error(value: JsonError.InvalidData)
    if describe_error(json) != "malformed JSON":
        return panic(message: "specific handler did not run")
    let io = Error(value: IoError.Failed(message: "disk diagnostic"))
    if describe_error(io) != "I/O: disk diagnostic":
        return panic(message: "specific handler lost diagnostic")
    let custom = Error(value: CustomError(detail: "application diagnostic"))
    if describe_error(custom) != "application diagnostic":
        return panic(message: "generic fallback did not use custom implementation")
    let wrapped = Error(value: json)
    if describe_error(wrapped) != "malformed JSON":
        return panic(message: "repeated views changed concrete identity")
    match propagate_generic():
        ok(_):
            return panic(message: "invalid data succeeded")
        error(cause):
            match cause:
                EncodingError(encoding):
                    if encoding != EncodingError.InvalidData:
                        return panic(message: "generic propagation lost original cause")
                _:
                    return panic(message: "generic propagation lost concrete type")

test "type patterns compare exact generic applications":
    let integer = Error(value: TaggedError(detail: 7))
    let text = Error(value: TaggedError(detail: "text diagnostic"))
    if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic":
        return panic(message: "type pattern ignored generic arguments")
    if not generic_type_pattern(cause: integer, expected: 1):
        return panic(message: "generic type pattern did not resolve its argument")
    if generic_type_pattern(cause: integer, expected: "different type"):
        return panic(message: "generic type pattern matched wrong application")

test "Error views can be stored and matched":
    let shared = Error(value: CustomError(detail: "shared diagnostic"))
    let errors: List[Error] = [shared]
    match errors.get(index: 0):
        some(cause):
            match cause:
                CustomError(custom):
                    if custom.detail != "shared diagnostic":
                        return panic(message: "shared view lost receiver")
                _:
                    return panic(message: "shared view lost type")
        none:
            return panic(message: "shared errors collection was empty")

import {LogError} from "@std/log.ms"
import {CommandError} from "@std/process.ms"
import {ExecutionError, StartError} from "@std/tasks.ms"
import {PoolError} from "@std/pools.ms"

test "standard diagnostics preserve messages and wrapped causes":
    let sink = LogError.Io(cause: IoError.Failed(message: "sink diagnostic"))
    if Error(value: sink).message() != "sink diagnostic":
        return panic(message: "log error lost underlying diagnostic")
    if Error(value: CommandError.Failed(message: "command diagnostic")).message() != "command diagnostic":
        return panic(message: "command error lost diagnostic")
    if Error(value: ExecutionError.TimedOut).message() != "ExecutionError.TimedOut":
        return panic(message: "execution error has no diagnostic")
    if Error(value: StartError.Full).message() != "StartError.Full":
        return panic(message: "start error has no diagnostic")
    if Error(value: PoolError.Closed).message() != "PoolError.Closed":
        return panic(message: "pool error has no diagnostic")

# The type-pattern rule also works for unrelated operation contracts.
interface Label[T]:
    fn label() -> T

type Labelled[T]:
    value: T

impl Label[T] for Labelled[T]:
    fn label() -> T:
        return self.value

fn match_label(view: Label[String]) -> String:
    match view:
        Labelled[String](receiver):
            return receiver.value
        _:
            return view.label()

import Synchronized from "@std/sync.ms"

fn counted_view(count: Synchronized[Int]) -> Label[String]:
    with locked = count.lock():
        locked.set(value: locked.get() + 1)
    return Label[String](value: Labelled(value: "label diagnostic"))

test "contract matches evaluate once and preserve ordinary contract semantics":
    let count = Synchronized(value: 0)
    match counted_view(count):
        Labelled[String](receiver):
            if receiver.value != "label diagnostic":
                return panic(message: "unrelated contract pattern lost receiver")
        _:
            return panic(message: "unrelated contract pattern did not run")
    with locked = count.lock():
        if locked.get() != 1:
            return panic(message: "contract scrutinee was evaluated more than once")
    let view = Label[String](value: Labelled(value: "separate handler"))
    if match_label(view) != "separate handler":
        return panic(message: "contract match depended on Error identity")
