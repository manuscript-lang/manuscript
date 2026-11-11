import (
	Bytes from "@std/bytes.ms",
	CsvOptions, parse, stringify from "@std/data/csv.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
	CommandOutput,
	Commands,
	RunOptions,
	SpawnOptions,
	Subprocess,
	run from "@std/os/process.ms",
	expect_equal, expect_false from "@std/test/test.ms",
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
	return ok((service.run("fake", [])?).stdout)

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
	expect_equal((concrete("fake", [])?).stdout, service.input)?

	commands: Commands := service
	viewed := commands.run
	expect_equal((viewed("fake", [])?).stdout.length(), 0)?

	explicit := "explicit".to_bytes()
	expect_equal(
		(viewed("fake", [], RunOptions(input: explicit.clone()))?).stdout, explicit
	)?

test "CSV defaults are fresh and explicit options retain their meaning":
	var first = CsvOptions()
	first.delimiter = ";"
	first.line_ending = "\r\n"

	second := CsvOptions()
	expect_false(
		(
			first.delimiter != ";"
			or second.delimiter != ","
			or second.line_ending != "\n"
		)
	)?
	expect_equal(CsvOptions("\t").line_ending, "\n")?
	expect_equal(CsvOptions(line_ending: "\r\n").delimiter, ",")?
	expect_equal((stringify([["a", "b"]])?), "a,b\n")?
	expect_equal((stringify([["a", "b"]], first)?), "a;b\r\n")?
	expect_equal((parse("a,b\n")?), [["a", "b"]])?

	bound := stringify
	expect_equal((bound([["a", "b"]])?), "a,b\n")?

	typed := forward(stringify)
	expect_equal((typed([["a", "b"]], second, none)?), "a,b\n")?

	limited: List[List[String]]! := error(
		Error("CSV: limit exceeded", kind: "EOVERFLOW")
	)
	expect_false(
		(
			parse("a,b\n", CsvOptions(max_cells: 1)) != limited
			or parse("a,b\n", CsvOptions(max_rows: 0)) != limited
		)
	)?

	invalid: String! := error(Error("CSV: invalid input", kind: "EINVAL"))
	expect_equal(stringify([["a"]], CsvOptions("")), invalid)?

test "Base64 defaults support stored functions and explicit alphabets":
	bytes := Bytes([255])
	expect_false(
		(
			base64_encode(bytes) != "/w=="
			or base64_encode(bytes, false) != "/w=="
		)
	)?
	expect_equal(base64_encode(bytes, true), "_w==")?

	encode := base64_encode
	copied := base64_encode
	expect_equal(copied(bytes), "/w==")?

	typed: fn(Bytes, Bool, Bool) String := encode
	expect_equal(typed(bytes, false, true), "/w==")?
	expect_false(
		(
			(base64_decode("/w==")?) != bytes
			or (base64_decode("_w==", true)?) != bytes
		)
	)?

	decode := base64_decode
	expect_equal((decode("/w==", max_bytes: 1)?), bytes)?

	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(base64_decode("_w=="), invalid)?

	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(base64_decode("/w==", max_bytes: 0), limited)?

test "Commands defaults cross concrete bound view and generic boundaries":
	capture := Capture("x".to_bytes())
	bound := capture.run
	expect_equal((bound("fake", [])?).stdout.length(), 0)?
	expect_equal((capture.run("fake", [])?).stdout.length(), 0)?

	view: Commands := Capture("x".to_bytes())
	viewed := view.run
	expect_equal((viewed("fake", [])?).stdout.length(), 0)?
	expect_equal((generic_run(Capture("x".to_bytes()))?).length(), 0)?

	input := Bytes([42])
	output := (view.run("fake", [], RunOptions(input: input.clone()))?).stdout
	expect_equal(output, input)?

	forwarded := forward(view.run)
	expect_equal(
		(forwarded("fake", [], RunOptions(input: input.clone()))?).stdout.get(
			0
		),
		42
	)?

	invalid: CommandOutput! := error(Error("process: invalid input", kind: "EINVAL"))
	native := run
	expect_equal(native("", []).wait(), invalid)?
