// The structured fault record a test process leaves behind (`MSFR` version 1, little
// endian: magic, version, pid, kind, flags, then length-prefixed strings and counts), read
// into the `fault` member of a failed test in the `--json` document.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	JsonValue from "@std/data/json.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	flag, list_of, number, object, text, with from "../json_out.ms",
)

export type Frame:
	file: String
	line: Int
	function: String
	repeated: Int

export type Fault:
	kind: String
	exit_code: Int
	message: String
	trace: List[Frame]
	truncated: Bool
	cleanup_faults: List[String]

// A byte string the record holds, and where the next field starts.
type Taken:
	text: String
	next: Int

fn kind_name(code: Int) String:
	names := [
		"fault", "incomplete_cleanup", "stack_overflow", "deadlock", "division_by_zero",
		"overflow", "index_out_of_range", "test_failure", "out_of_memory"
	]
	if code >= 0 and code < names.length(): return names[code].clone()

	return "fault"

// 134 for a fault, 139 for a stack overflow or out of memory, 1 for a failed test.
fn exit_status(code: Int) Int:
	if code == 7: return 1
	if code == 2 or code == 8: return 139

	return 134

// Whether `status` is how a program that ended in a runtime fault exits.
export fn is_fault_status(status: Int) Bool:
	return status == 134 or status == 139

fn word(data: Bytes, at: Int) Int!:
	return ok(data.uint32_le(at)?.to_int())

fn take(data: Bytes, at: Int) Taken!:
	size := word(data, at)?
	end := at + 4 + size
	if end > data.length(): return error(Error("short record"))

	return ok(Taken(data.decode_utf8_range(at + 4, end).get_or(""), end))

// A record as the process wrote it: the fault, whether it is a failed expectation, and
// where that expectation was built.
export type Written:
	fault: Fault
	test_failure: Bool
	site: String = ""
	has_site: Bool = false

// The fault a record describes; none when `data` is not a record of this version.
export fn decode(data: Bytes) Fault?:
	written := decode_written(data)
	if written.is_none(): return none

	return written.get().fault.clone()

export fn decode_written(data: Bytes) Written?:
	parsed := decode_checked(data)
	if parsed.is_error(): return none

	return parsed.get()

fn decode_checked(data: Bytes) Written!:
	if data.length() < 11: return error(Error("short record"))
	if data.decode_utf8_range(0, 4).get_or("") != "MSFR" or data.get(4) != 1:
		return error(Error("not a record"))

	code := data.get(9).to_int()
	flags := data.get(10).to_int()
	message := take(data, 11)?
	var at = message.next
	frames := word(data, at)?
	at += 4

	var trace = List[Frame]()

	for frame_at in 0..frames:
		file := take(data, at)?
		line := word(data, file.next)?
		function := take(data, file.next + 4)?
		repeated := word(data, function.next)?
		at = function.next + 4
		trace.append(Frame(file.text, line, function.text, repeated))

	cleanups := word(data, at)?
	at += 4

	var cleanup_faults = List[String]()

	for cleanup_at in 0..cleanups:
		one := take(data, at)?
		at = one.next
		cleanup_faults.append(one.text)

	var written = Written(
		Fault(
			kind_name(code),
			exit_status(code),
			message.text,
			trace,
			flags % 2 == 1,
			cleanup_faults,
		),
		code == 7,
	)

	if flags >= 2 and flags % 4 >= 2:
		site := take(data, at)?
		written.site = site.text
		written.has_site = true

	return ok(written)

// A fault with only the text the program printed, for an exit without a record.
export fn from_text(message: String) Fault?:
	trimmed := message.trim_end_chars("\n")
	if trimmed.is_empty(): return none

	return Fault("fault", 134, trimmed, [], false, [])

export fn fault_json(fault: Fault) JsonValue:
	var frames = List[JsonValue]()

	for frame in fault.trace:
		var item = object()
		item = with(item, "function", text(frame.function))
		item = with(item, "file", text(frame.file))
		item = with(item, "line", number(frame.line))
		if frame.repeated > 0: item = with(item, "repeated", number(frame.repeated))
		frames.append(item)

	var out = object()
	out = with(out, "kind", text(fault.kind))
	out = with(out, "message", text(fault.message))

	if top := fault.trace.first():
		var position = object()
		position = with(position, "file", text(top.file))
		position = with(position, "line", number(top.line))
		out = with(out, "position", position)

	var cleanups = List[JsonValue]()
	for cleanup in fault.cleanup_faults: cleanups.append(text(cleanup))
	out = with(out, "trace", list_of(frames))
	out = with(out, "trace_truncated", flag(fault.truncated))
	out = with(out, "cleanups_ran", flag(true))
	out = with(out, "cleanup_faults", list_of(cleanups))
	out = with(out, "exit_code", number(fault.exit_code))
	return out

test "a text fault has the fault kind and no trace":
	fault := from_text("boom\n")
	expect_true(fault.is_some())?
	expect_equal(fault.get().message, "boom")?
	expect_equal(fault.get().exit_code, 134)?
	expect_true(from_text("\n").is_none())?

test "a record that is not one decodes to none":
	expect_true(decode("nope".to_bytes()).is_none())?

fn put(var out: BytesBuilder, value: String) Void:
	bytes := value.to_bytes()
	out.append_uint32_le(bytes.length().to_uint32().get())
	out.append_bytes(bytes)

test "a record decodes to its kind, message, trace and cleanups":
	var out = BytesBuilder()
	out.append_bytes("MSFR".to_bytes())
	out.append(1)
	out.append_uint32_le(77)
	out.append(2)
	out.append(1)
	put(out, "deep")
	out.append_uint32_le(1)
	put(out, "a.ms")
	out.append_uint32_le(9)
	put(out, "f")
	out.append_uint32_le(3)
	out.append_uint32_le(1)
	put(out, "late")

	fault := decode(out.build())
	expect_true(fault.is_some())?
	expect_equal(fault.get().kind, "stack_overflow")?
	expect_equal(fault.get().exit_code, 139)?
	expect_equal(fault.get().message, "deep")?
	expect_true(fault.get().truncated)?
	expect_equal(fault.get().trace[0].line, 9)?
	expect_equal(fault.get().trace[0].repeated, 3)?
	expect_equal(fault.get().cleanup_faults[0], "late")?
