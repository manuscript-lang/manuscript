# conform: tags=aliasing,closures,control-flow,faults,generics,interfaces,lists,match,modules,mutation,optional,records,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-process,stdlib-testing,stdlib-time,strings,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/defaults.ms
from "@std/testing.ms" import expect_equal, expect_false
from "@std/csv.ms" import parse, stringify, CsvOptions, CsvError
from "@std/encoding.ms" import base64_encode, base64_decode, EncodingError
from "@std/process.ms" import Commands, Subprocess, CommandOutput, CommandError, commands
from "@std/bytes.ms" import Bytes

def forward[T](item: T) -> T: item

type Capture:
    last: Bytes
    calls: Int

impl Commands for Capture:
    def run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int],
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        self.last = input
        self.calls += 1
        return ok(CommandOutput(0, input, "".to_bytes()))

    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

from "@std/time.ms" import Duration

def generic_run[T: Commands](service: T) -> Result[Bytes, Error]:
    return ok((try service.run("fake", [])).stdout)

type Override:
    input: Bytes

test "bound receiver is captured before supplied arguments":
    let first = Capture("first".to_bytes(), 0)
    let second = Capture("second".to_bytes(), 0)
    var selected = first
    let index: Optional[Int] = some(0)
    let output = try selected.run(
        match index:
            case some(_):
                selected = second
                "fake"
            case none: "fake"
        ,
        []
    )
    try expect_false(
        (first.calls != 1 or second.calls != 0 or output.stdout.length() != 0)
    )

impl Commands for Override:
    def run(
        program: String,
        arguments: List[String],
        input: Bytes = self.input,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        return ok(CommandOutput(0, input, "".to_bytes()))

    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

test "concrete implementation defaults and interface defaults stay distinct":
    let service = Override("custom".to_bytes())
    let concrete = service.run
    try expect_equal((try concrete("fake", [])).stdout, service.input)

    let viewed = Commands(service).run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)

    let explicit = "explicit".to_bytes()
    try expect_equal((try viewed("fake", [], explicit)).stdout, explicit)

test "CSV defaults are fresh and explicit options retain their meaning":
    let first = CsvOptions()
    var alias = first
    alias.delimiter = ";"
    alias.line_ending = "\r\n"

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

    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    try expect_false(
        (
            parse("a,b\n", max_cells: 1) != limited
            or parse("a,b\n", max_rows: 0) != limited
        )
    )

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    try expect_equal(stringify([["a"]], CsvOptions("")), invalid)

test "Base64 defaults support stored functions and explicit alphabets":
    let bytes = Bytes([255])
    try expect_false(
        (
            base64_encode(bytes) != "/w=="
            or base64_encode(bytes, False) != "/w=="
        )
    )
    try expect_equal(base64_encode(bytes, True), "_w==")

    let encode = base64_encode
    let copied = encode
    try expect_equal(copied(bytes), "/w==")

    let typed: Callable[[Bytes, Bool], String] = encode
    try expect_equal(typed(bytes, False), "/w==")
    try expect_false(
        (
            (try base64_decode("/w==")) != bytes
            or (try base64_decode("_w==", True)) != bytes
        )
    )

    let decode = base64_decode
    try expect_equal((try decode("/w==", max_bytes: 1)), bytes)

    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    try expect_equal(base64_decode("_w=="), invalid)

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    try expect_equal(base64_decode("/w==", max_bytes: 0), limited)

test "Commands defaults cross concrete bound view and generic boundaries":
    let capture = Capture("x".to_bytes(), 0)
    let bound = capture.run
    try expect_equal((try bound("fake", [])).stdout.length(), 0)
    try expect_equal((try capture.run("fake", [])).stdout.length(), 0)

    let view = Commands(capture)
    let viewed = view.run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)
    try expect_equal((try generic_run(capture)).length(), 0)

    let input = Bytes([42])
    let output = (try view.run("fake", [], input)).stdout
    try expect_false(output != input or capture.last != input)

    let forwarded = forward(view.run)
    try expect_equal((try forwarded("fake", [], input, none, none)).stdout.get(0), 42)
    try expect_equal(capture.calls, 6)

    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    let native = commands().run
    try expect_equal(native("", []), invalid)
