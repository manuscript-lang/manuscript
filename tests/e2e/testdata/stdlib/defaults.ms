import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"
import {base64_encode, base64_decode, EncodingError} from "@std/encoding.ms"
import {Commands, Subprocess, CommandOutput, CommandError, commands} from "@std/process.ms"
import Bytes from "@std/bytes.ms"

fn forward[T](item: T) -> T: item

type Capture:
    last: Bytes
    calls: Int

impl Commands for Capture:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int],
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        self.last = input
        self.calls = self.calls + 1
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(
        program: String,
        arguments: List[String]
    ) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

import Duration from "@std/time.ms"

fn generic_run[T: Commands](service: T) -> Result[Bytes, Error]:
    return ok((service.run(program: "fake", arguments: []) | try expect_ok).stdout)

type Override:
    input: Bytes

test "bound receiver is captured before supplied arguments":
    let first = Capture("first".to_bytes(), 0)
    let second = Capture("second".to_bytes(), 0)
    var selected = first
    let index: Optional[Int] = some(0)
    let output = (
        try expect_ok(
            selected.run(
                program: match index:
                    some(_):
                        selected = second
                        "fake"
                    none: "fake"
                ,
                arguments: []
            )
        )
    )
    (first.calls != 1 or second.calls != 0 or output.stdout.length() != 0) | try expect_false

impl Commands for Override:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = self.input,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(
        program: String,
        arguments: List[String]
    ) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

test "concrete implementation defaults and interface defaults stay distinct":
    let service = Override("custom".to_bytes())
    let concrete = service.run
    (concrete(program: "fake", arguments: []) | try expect_ok).stdout | try expect_equal(
        expected: service.input
    )
    let viewed = Commands(service).run
    ((viewed(program: "fake", arguments: []) | try expect_ok).stdout.length()) | try expect_equal(
        expected: 0
    )
    let explicit = "explicit".to_bytes()
    (
        (
            (
                viewed(
                    program: "fake",
                    arguments: [],
                    input: explicit
                ) | try expect_ok
            ).stdout != explicit
        )
    ) | try expect_false

test "CSV defaults are fresh and explicit options retain their meaning":
    let first = CsvOptions()
    let alias = first
    alias.delimiter = ";"
    alias.line_ending = "\r\n"
    let second = CsvOptions()
    (first.delimiter != ";" or second.delimiter != "," or second.line_ending != "\n") | try expect_false
    CsvOptions(delimiter: "\t").line_ending | try expect_equal(expected: "\n")
    CsvOptions(line_ending: "\r\n").delimiter | try expect_equal(expected: ",")
    stringify([["a", "b"]]) | try expect_ok | try expect_equal(expected: "a,b\n")
    stringify([["a", "b"]], options: first) | try expect_ok | try expect_equal(
        expected: "a;b\r\n"
    )
    parse("a,b\n") | try expect_ok | try expect_equal(expected: [["a", "b"]])
    let bound = stringify
    bound([["a", "b"]]) | try expect_ok | try expect_equal(expected: "a,b\n")
    let typed = forward(stringify)
    typed([["a", "b"]], second, none) | try expect_ok | try expect_equal(
        expected: "a,b\n"
    )
    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    (
        (
            parse("a,b\n", max_cells: 1) != limited
            or parse("a,b\n", max_rows: 0) != limited
        )
    ) | try expect_false
    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    stringify([["a"]], options: CsvOptions(delimiter: "")) | try expect_equal(
        expected: invalid
    )

test "Base64 defaults support stored functions and explicit alphabets":
    let bytes = Bytes([255])
    (base64_encode(bytes) != "/w==" or base64_encode(bytes, false) != "/w==") | try expect_false
    base64_encode(bytes, true) | try expect_equal(expected: "_w==")
    let encode = base64_encode
    let copied = encode
    copied(bytes) | try expect_equal(expected: "/w==")
    let typed: fn(data: Bytes, url_safe: Bool) -> String = encode
    typed(bytes, false) | try expect_equal(expected: "/w==")
    (
        (
            (base64_decode("/w==") | try expect_ok) != bytes
            or (base64_decode("_w==", true) | try expect_ok) != bytes
        )
    ) | try expect_false
    let decode = base64_decode
    decode("/w==", max_bytes: 1) | try expect_ok | try expect_equal(expected: bytes)
    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    base64_decode("_w==") | try expect_equal(expected: invalid)
    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    base64_decode("/w==", max_bytes: 0) | try expect_equal(expected: limited)

test "Commands defaults cross concrete bound view and generic boundaries":
    let capture = Capture("x".to_bytes(), 0)
    let bound = capture.run
    ((bound(program: "fake", arguments: []) | try expect_ok).stdout.length()) | try expect_equal(
        expected: 0
    )
    (
        (
            capture.run(program: "fake", arguments: []) | try expect_ok
        ).stdout.length() | try expect_equal(expected: 0)
    )
    let view = Commands(capture)
    let viewed = view.run
    ((viewed(program: "fake", arguments: []) | try expect_ok).stdout.length()) | try expect_equal(
        expected: 0
    )
    (try generic_run(capture)).length() | try expect_equal(expected: 0)
    let input = Bytes([42])
    let output = (
        view.run(program: "fake", arguments: [], input: input) | try expect_ok
    ).stdout
    (output != input or capture.last != input) | try expect_false
    let forwarded = forward(view.run)
    ((forwarded("fake", [], input, none, none) | try expect_ok).stdout.at(0).unwrap()) | try expect_equal(
        expected: 42
    )
    capture.calls | try expect_equal(expected: 6)
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    let native = commands().run
    native(program: "", arguments: []) | try expect_equal(expected: invalid)
