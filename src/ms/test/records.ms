// The records a test executable appends to its results file (`MS_TEST_RESULTS`). Each
// is one line led by U+0001 and a tag; `MSOUT` is followed by that many bytes of
// payload and a newline. The format is written by `src/stdlib/internal/test_runner.ms`.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

export enum Kind:
	// A test began: `index` and `file`.
	Start
	// A test ended: `index`, `status`, `nanos`, `message` and `site`.
	Result
	// A test of `file` faulted, with `message`.
	Fault
	// Output of a test (`index`), of a faulted file (`key` "f<file>") or its fault
	// record (`key` "r<file>"): `payload`.
	Output

export type Record:
	kind: Kind
	index: Int = -1
	file: Int = -1
	status: String = ""
	nanos: Int = 0
	message: String = ""
	site: String = ""
	key: String = ""
	payload: Bytes = "".to_bytes()

// The whole records at the start of the bytes given, and how many bytes they took; a
// trailing partial record is left for the next read.
export type Parsed:
	records: List[Record] = []
	used: Int = 0

START := "\u{1}MSSTART "
RESULT := "\u{1}MSTEST "
FAULT := "\u{1}MSFAULT "
OUTPUT := "\u{1}MSOUT "

// The text between `start` and `end` of `data`.
fn slice_text(data: Bytes, start: Int, end: Int) String:
	return data.decode_utf8_range(start, end).get_or("")

// The record a line (without its newline) says, when it is one that carries no payload.
fn parse_line(line: String) Record?:
	if line.starts_with(START):
		words := line.slice(START.length(), line.length()).split(" ")
		if words.length() < 2: return none

		index := words[0].parse_int()
		file := words[1].parse_int()
		if index.is_none() or file.is_none(): return none

		return Record(kind: Kind.Start, index: index.get(), file: file.get())

	if line.starts_with(FAULT):
		rest := line.slice(FAULT.length(), line.length())
		parts := rest.split("\u{1}")
		file := parts[0].parse_int()
		if file.is_none(): return none

		message := if parts.length() > 1: parts[1].replace("\u{2}", "\n") else: ""
		return Record(kind: Kind.Fault, file: file.get(), message: message)

	if line.starts_with(RESULT):
		rest := line.slice(RESULT.length(), line.length())
		parts := rest.split("\u{1}")
		words := parts[0].split(" ")
		index := if words.length() > 0: words[0].parse_int() else: none
		if index.is_none(): return none

		status := if words.length() > 1: words[1].clone() else: ""
		nanos := if words.length() > 2: words[2].parse_int().get_or(0) else: 0
		message := if parts.length() > 1: parts[1].clone() else: ""
		site := if parts.length() > 2: parts[2].clone() else: ""
		return Record(
			kind: Kind.Result,
			index: index.get(),
			status: status,
			nanos: nanos,
			message: message,
			site: site,
		)

	return none

// Reads the whole records at the start of `data`.
export fn parse(data: Bytes) Parsed:
	var out = Parsed()
	var at = 0
	size := data.length()

	while at < size:
		found := data.index_of_byte(10, at)
		if found.is_none(): break

		end := found.get()
		line := slice_text(data, at, end)
		next := end + 1

		if line.starts_with(OUTPUT):
			rest := line.slice(OUTPUT.length(), line.length()).split(" ")
			length := if rest.length() > 1: rest[1].parse_int().get_or(0) else: 0
			if size < next + length + 1: break

			out.records.append(
				Record(
					kind: Kind.Output,
					key: rest[0].clone(),
					payload: data.view(next, next + length).clone(),
				)
			)
			at = next + length + 1
			out.used = at
			continue

		if record := parse_line(line):
			out.records.append(record)
		at = next
		out.used = at

	return out

test "a start, a result and a fault":
	text := "\u{1}MSSTART 3 1\n\u{1}MSTEST 3 fail 1500\u{1}boom\u{1}a.ms:4:2\n\u{1}MSFAULT 1\u{1}a\u{2}b\n"
	parsed := parse(text.to_bytes())
	parsed.records.length() | expect_equal(expected: 3)?
	parsed.used | expect_equal(expected: text.to_bytes().length())?
	parsed.records[0].index | expect_equal(expected: 3)?
	parsed.records[1].status | expect_equal(expected: "fail")?
	parsed.records[1].nanos | expect_equal(expected: 1500)?
	parsed.records[1].site | expect_equal(expected: "a.ms:4:2")?
	parsed.records[2].message | expect_equal(expected: "a\nb")?

test "output carries its bytes and waits for them":
	whole := "\u{1}MSOUT 2 5\nhi\nyo\n"
	parsed := parse(whole.to_bytes())
	parsed.records.length() | expect_equal(expected: 1)?
	parsed.records[0].key | expect_equal(expected: "2")?
	parsed.records[0].payload.length() | expect_equal(expected: 5)?

	cut := parse("\u{1}MSOUT 2 5\nhi".to_bytes())
	cut.records.length() | expect_equal(expected: 0)?
	cut.used | expect_equal(expected: 0)?
