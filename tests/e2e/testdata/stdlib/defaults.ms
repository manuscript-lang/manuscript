import {parse, stringify, CsvOptions, CsvError} from "@std/csv.ms"
import {base64_encode, base64_decode, EncodingError} from "@std/encoding.ms"
import {Commands, Subprocess, CommandOutput, CommandError, commands} from "@std/process.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

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

    fn spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

import Duration from "@std/time.ms"

fn generic_run[T: Commands](service: T) -> Bytes:
    return value(service.run(program: "fake", arguments: [])).stdout

type Override:
    input: Bytes

test "bound receiver is captured before supplied arguments":
    let first = Capture("first".to_bytes(), 0)
    let second = Capture("second".to_bytes(), 0)
    var selected = first
    let index: Optional[Int] = some(0)
    let output = value(
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
    if (first.calls != 1 or second.calls != 0 or output.stdout.length() != 0):
        return panic("receiver capture order changed")

impl Commands for Override:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes = self.input,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

test "concrete implementation defaults and interface defaults stay distinct":
    let service = Override("custom".to_bytes())
    let concrete = service.run
    if value(concrete(program: "fake", arguments: [])).stdout != service.input:
        return panic("concrete input override")

    let viewed = Commands(service).run
    if value(viewed(program: "fake", arguments: [])).stdout.length() != 0:
        return panic("interface input default")

    let explicit = "explicit".to_bytes()
    if (
        value(
            viewed(program: "fake", arguments: [], input: explicit)
        ).stdout != explicit
    ):
        return panic("explicit input skips both defaults")

test "CSV defaults are fresh and explicit options retain their meaning":
    let first = CsvOptions()
    let alias = first
    alias.delimiter = ";"
    alias.line_ending = "\r\n"
    let second = CsvOptions()
    if (first.delimiter != ";" or second.delimiter != "," or second.line_ending != "\n"):
        return panic("CSV construction must allocate fresh mutable storage")
    if CsvOptions(delimiter: "\t").line_ending != "\n": return panic("ending default")
    if CsvOptions(line_ending: "\r\n").delimiter != ",": return panic(
        "delimiter default"
    )
    if value(stringify([["a", "b"]])) != "a,b\n": return panic("CSV default output")
    if value(stringify([["a", "b"]], options: first)) != "a;b\r\n":
        return panic("explicit CSV options")
    if value(parse("a,b\n")) != [["a", "b"]]: return panic("CSV default parse")

    let bound = stringify
    if value(bound([["a", "b"]])) != "a,b\n": return panic("stored CSV default")

    let typed = forward(stringify)
    if value(typed([["a", "b"]], second, none)) != "a,b\n":
        return panic("generic forwarding with full arguments")

    let limited: Result[List[List[String]], CsvError] = error(CsvError.LimitExceeded)
    if (
        parse("a,b\n", max_cells: 1) != limited
        or parse("a,b\n", max_rows: 0) != limited
    ):
        return panic("distinct CSV budgets")

    let invalid: Result[String, CsvError] = error(CsvError.InvalidInput)
    if stringify([["a"]], options: CsvOptions(delimiter: "")) != invalid:
        return panic("explicit invalid options still validate")

test "Base64 defaults support stored functions and explicit alphabets":
    let bytes = Bytes([255])
    if base64_encode(bytes) != "/w==" or base64_encode(bytes, false) != "/w==":
        return panic("standard alphabet")
    if base64_encode(bytes, true) != "_w==": return panic("URL alphabet")

    let encode = base64_encode
    let copied = encode
    if copied(bytes) != "/w==": return panic("copied native callable")

    let typed: fn(data: Bytes, url_safe: Bool) -> String = encode
    if typed(bytes, false) != "/w==": return panic("complete typed callable")
    if (
        value(base64_decode("/w==")) != bytes
        or value(base64_decode("_w==", true)) != bytes
    ):
        return panic("decode alphabet")

    let decode = base64_decode
    if value(decode("/w==", max_bytes: 1)) != bytes: return panic(
        "stored decode default"
    )

    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    if base64_decode("_w==") != invalid: return panic("default rejects URL alphabet")

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    if base64_decode("/w==", max_bytes: 0) != limited: return panic("zero is present")

test "Commands defaults cross concrete bound view and generic boundaries":
    let capture = Capture("x".to_bytes(), 0)
    let bound = capture.run
    if value(bound(program: "fake", arguments: [])).stdout.length() != 0:
        return panic("bound input default")
    if value(capture.run(program: "fake", arguments: [])).stdout.length() != 0:
        return panic("concrete input default")

    let view = Commands(capture)
    let viewed = view.run
    if value(viewed(program: "fake", arguments: [])).stdout.length() != 0:
        return panic("viewed input default")
    if generic_run(capture).length() != 0: return panic("bounded generic input default")

    let input = Bytes([42])
    let output = value(view.run(program: "fake", arguments: [], input: input)).stdout
    if output != input or capture.last != input:
        return panic("explicit input payload retains value")

    let forwarded = forward(view.run)
    if value(forwarded("fake", [], input, none, none)).stdout.at(0).unwrap() != 42:
        return panic("generic forwarding preserves full callable ABI")
    if capture.calls != 6: return panic("each invocation executes once")

    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    let native = commands().run
    if native(program: "", arguments: []) != invalid:
        return panic("native empty stdin default reaches validation")
