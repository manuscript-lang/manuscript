# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,lists,match,modules,mutation,optional,parser,records,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-process,stdlib-testing,stdlib-time,strings,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/defaults.ms
import expect_equal, expect_false from "@std/test.ms"
import parse, stringify, CsvOptions, CsvError from "@std/csv.ms"
import base64_encode, base64_decode, EncodingError from "@std/encoding.ms"
import Commands, Subprocess, CommandOutput, CommandError, run, Stdio from "@std/process.ms"
import Bytes from "@std/bytes.ms"

fn forward[T](item: T) T: item

type Capture:
    tag: Bytes

impl Commands for Capture:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Int?,
        timeout: Duration?
    ) CommandOutput!CommandError:
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio,
        stdout: Stdio,
        stderr: Stdio
    ) Subprocess!CommandError:
        return error(CommandError.Unavailable)

import Duration from "@std/time.ms"

fn generic_run[T: Commands](service: T) Bytes!:
    return ok((try service.run("fake", [])).stdout)

type Override:
    input: Bytes

impl Commands for Override:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = self.input,
        max_output_bytes: Int?,
        timeout: Duration?
    ) CommandOutput!CommandError:
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio,
        stdout: Stdio,
        stderr: Stdio
    ) Subprocess!CommandError:
        return error(CommandError.Unavailable)

test "concrete implementation defaults and interface defaults stay distinct":
    let service = Override("custom".to_bytes())
    let concrete = service.run
    try expect_equal((try concrete("fake", [])).stdout, service.input)

    let commands: Commands = service
    let viewed = commands.run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)

    let explicit = "explicit".to_bytes()
    try expect_equal((try viewed("fake", [], explicit)).stdout, explicit)

test "CSV defaults are fresh and explicit options retain their meaning":
    var first = CsvOptions()
    first.delimiter = ";"
    first.line_ending = "\r\n"

    let second = CsvOptions()
    try expect_false(
        (
            first.delimiter != ";"
            or second.delimiter != ","
            or second.line_ending != "\n"
        )
    )
    try expect_equal(CsvOptions("\t").line_ending, "\n")
    try expect_equal(CsvOptions(line_ending: "\r\n").delimiter, ",")
    try expect_equal((try stringify([["a", "b"]])), "a,b\n")
    try expect_equal((try stringify([["a", "b"]], first)), "a;b\r\n")
    try expect_equal((try parse("a,b\n")), [["a", "b"]])

    let bound = stringify
    try expect_equal((try bound([["a", "b"]])), "a,b\n")

    let typed = forward(stringify)
    try expect_equal((try typed([["a", "b"]], second, none)), "a,b\n")

    let limited: List[List[String]]!CsvError = error(CsvError.LimitExceeded)
    try expect_false(
        (
            parse("a,b\n", max_cells: 1) != limited
            or parse("a,b\n", max_rows: 0) != limited
        )
    )

    let invalid: String!CsvError = error(CsvError.InvalidInput)
    try expect_equal(stringify([["a"]], CsvOptions("")), invalid)

test "Base64 defaults support stored functions and explicit alphabets":
    let bytes = Bytes([255])
    try expect_false(
        (
            base64_encode(bytes) != "/w=="
            or base64_encode(bytes, false) != "/w=="
        )
    )
    try expect_equal(base64_encode(bytes, true), "_w==")

    let encode = base64_encode
    let copied = base64_encode
    try expect_equal(copied(bytes), "/w==")

    let typed: fn(Bytes, Bool) String = encode
    try expect_equal(typed(bytes, false), "/w==")
    try expect_false(
        (
            (try base64_decode("/w==")) != bytes
            or (try base64_decode("_w==", true)) != bytes
        )
    )

    let decode = base64_decode
    try expect_equal((try decode("/w==", max_bytes: 1)), bytes)

    let invalid: Bytes!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(base64_decode("_w=="), invalid)

    let limited: Bytes!EncodingError = error(EncodingError.LimitExceeded)
    try expect_equal(base64_decode("/w==", max_bytes: 0), limited)

test "Commands defaults cross concrete bound view and generic boundaries":
    let capture = Capture("x".to_bytes())
    let bound = capture.run
    try expect_equal((try bound("fake", [])).stdout.length(), 0)
    try expect_equal((try capture.run("fake", [])).stdout.length(), 0)

    let view: Commands = Capture("x".to_bytes())
    let viewed = view.run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)
    try expect_equal((try generic_run(Capture("x".to_bytes()))).length(), 0)

    let input = Bytes([42])
    let output = (try view.run("fake", [], input)).stdout
    try expect_equal(output, input)

    let forwarded = forward(view.run)
    try expect_equal((try forwarded("fake", [], input, none, none)).stdout.get(0), 42)

    let invalid: CommandOutput!CommandError = error(CommandError.InvalidInput)
    let native = run
    try expect_equal(native("", []), invalid)
