import (
	panic from "@std/core.ms",
	CsvOptions, stringify from "@std/data/csv.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	monotonic from "@std/time.ms",
)

fn work(
	rows: List[List[String]],
	options: CsvOptions,
	expected: String,
	kind: String,
	limit: Int,
	count: Int,
) Int:
	var checksum = 0

	for unused in 0..count:
		value := stringify(rows, options, limit)

		if kind != "OK":
			if value.is_ok() or value.err().kind != kind: panic("wrong error")

			message := if kind == "EOVERFLOW": "CSV: limit exceeded" else: "CSV: invalid input"
			if value.err().message != message: panic("wrong message")
			checksum += 1
		else:
			output := value.get()
			if output != expected: panic("wrong output")
			checksum += output.byte_length() + 1

	return checksum

export fn main() Int:
	args := arguments()
	field := read_file(args[0]).wait().get().decode_utf8().get()
	expected := read_file(args[1]).wait().get().decode_utf8().get()
	delimiter := args[2]
	ending := if args[3] == "crlf": "\r\n" else: "\n"
	options := CsvOptions(delimiter: delimiter.clone(), line_ending: ending)
	rows := [[field, "tail"]]
	kind := args[4]
	limit := args[5].parse_int().get()
	count := args[6].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work(rows, options, expected, kind, limit, warm)
	start := monotonic()
	checksum := work(rows, options, expected, kind, limit, count)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0
