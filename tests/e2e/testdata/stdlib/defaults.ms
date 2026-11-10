import (
    expect_equal, expect_false from "@std/test/test.ms",
    parse, stringify, CsvOptions from "@std/data/csv.ms",
    base64_encode, base64_decode from "@std/data/encoding.ms",
    Commands,
    Subprocess,
    CommandOutput,
    RunOptions,
    SpawnOptions,
    run from "@std/os/process.ms",
    Bytes from "@std/bytes.ms",
)

fn forward[T](item: T) T: item

type Capture:
    tag: Bytes

impl Commands for Capture:
    fn run(program: String, arguments: List[String], options: RunOptions) CommandOutput!:
        return ok(CommandOutput(0, options.input.clone(), "".to_bytes(), 0))

    fn spawn(
        program: String,
        arguments: List[String],
        options: SpawnOptions
    ) Subprocess!:
        return error(Error("process: service unavailable", kind: "EAGAIN"))

fn generic_run[T: Commands](service: T) Bytes!:
    return ok((try service.run("fake", [])).stdout)

type Override:
    input: Bytes

impl Commands for Override:
    fn run(
        program: String,
        arguments: List[String],
        options: RunOptions = RunOptions(input: self.input.clone())
    ) CommandOutput!:
        return ok(CommandOutput(0, options.input.clone(), "".to_bytes(), 0))

    fn spawn(
        program: String,
        arguments: List[String],
        options: SpawnOptions
    ) Subprocess!:
        return error(Error("process: service unavailable", kind: "EAGAIN"))

test "concrete implementation defaults and interface defaults stay distinct":
    service := Override("custom".to_bytes())
    concrete := service.run
    try expect_equal((try concrete("fake", [])).stdout, service.input)

    commands: Commands = service
    viewed := commands.run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)

    explicit := "explicit".to_bytes()
    try expect_equal(
        (try viewed("fake", [], RunOptions(input: explicit.clone()))).stdout, explicit
    )

test "CSV defaults are fresh and explicit options retain their meaning":
    var first = CsvOptions()
    first.delimiter = ";"
    first.line_ending = "\r\n"

    second := CsvOptions()
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

    bound := stringify
    try expect_equal((try bound([["a", "b"]])), "a,b\n")

    typed := forward(stringify)
    try expect_equal((try typed([["a", "b"]], second, none)), "a,b\n")

    limited: List[List[String]]! = error(
        Error("CSV: limit exceeded", kind: "EOVERFLOW")
    )
    try expect_false(
        (
            parse("a,b\n", CsvOptions(max_cells: 1)) != limited
            or parse("a,b\n", CsvOptions(max_rows: 0)) != limited
        )
    )

    invalid: String! = error(Error("CSV: invalid input", kind: "EINVAL"))
    try expect_equal(stringify([["a"]], CsvOptions("")), invalid)

test "Base64 defaults support stored functions and explicit alphabets":
    bytes := Bytes([255])
    try expect_false(
        (
            base64_encode(bytes) != "/w=="
            or base64_encode(bytes, false) != "/w=="
        )
    )
    try expect_equal(base64_encode(bytes, true), "_w==")

    encode := base64_encode
    copied := base64_encode
    try expect_equal(copied(bytes), "/w==")

    typed: fn(Bytes, Bool, Bool) String = encode
    try expect_equal(typed(bytes, false, true), "/w==")
    try expect_false(
        (
            (try base64_decode("/w==")) != bytes
            or (try base64_decode("_w==", true)) != bytes
        )
    )

    decode := base64_decode
    try expect_equal((try decode("/w==", max_bytes: 1)), bytes)

    invalid: Bytes! = error(Error("encoding: invalid data", kind: "EBADMSG"))
    try expect_equal(base64_decode("_w=="), invalid)

    limited: Bytes! = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
    try expect_equal(base64_decode("/w==", max_bytes: 0), limited)

test "Commands defaults cross concrete bound view and generic boundaries":
    capture := Capture("x".to_bytes())
    bound := capture.run
    try expect_equal((try bound("fake", [])).stdout.length(), 0)
    try expect_equal((try capture.run("fake", [])).stdout.length(), 0)

    view: Commands = Capture("x".to_bytes())
    viewed := view.run
    try expect_equal((try viewed("fake", [])).stdout.length(), 0)
    try expect_equal((try generic_run(Capture("x".to_bytes()))).length(), 0)

    input := Bytes([42])
    output := (try view.run("fake", [], RunOptions(input: input.clone()))).stdout
    try expect_equal(output, input)

    forwarded := forward(view.run)
    try expect_equal(
        (
            try forwarded("fake", [], RunOptions(input: input.clone()))
        ).stdout.get(0),
        42
    )

    invalid: CommandOutput! = error(Error("process: invalid input", kind: "EINVAL"))
    native := run
    try expect_equal(native("", []).wait(), invalid)
