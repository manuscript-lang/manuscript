import (
	stdout from "@std/io/io.ms",
	decode_component, encode_component, parse from "@std/net/url.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	count := args[0].parse_int().get()
	operation := args[1]
	input := args[2]
	expected_status := args[3]
	expected_0 := args[4]
	expected_1 := args[5]
	expected_2 := args[6]
	expected_3 := args[7]
	expected_4 := args[8]
	expected_5 := args[9]
	var checksum = 0
	var status = "OK"
	var f0 = ""
	var f1 = ""
	var f2 = ""
	var f3 = ""
	var f4 = ""
	var f5 = ""
	started := monotonic()

	for i in 0..count:
		if operation == "encode":
			f0 = encode_component(input)
		else if operation == "decode":
			result := decode_component(input)

			if result.is_error():
				if result.err().kind != "EBADMSG": return 1

				status = "InvalidData"
			else:
				f0 = result.get()
		else if operation == "parse":
			result := parse(input)

			if result.is_error():
				if result.err().kind != "EBADMSG": return 1

				status = "InvalidData"
			else:
				value := result.get()
				f0 = value.scheme
				f1 = value.host

				port := value.port.get(-1)
				f2 = "{port}"
				f3 = value.path
				f4 = value.query
				f5 = value.fragment
		else:
			return 1

		if status != expected_status: return 1
		if f0 != expected_0: return 1
		if f1 != expected_1: return 1
		if f2 != expected_2: return 1
		if f3 != expected_3: return 1
		if f4 != expected_4: return 1
		if f5 != expected_5: return 1

		checksum += f0.byte_length() + f1.byte_length() + f2.byte_length()
		checksum += f3.byte_length() + f4.byte_length() + f5.byte_length()
		if status == "InvalidData":
			checksum += 1

	ns := monotonic().difference(started).to_nanoseconds()
	(
		stdout().write(
			"{count}\t{ns}\t{checksum}\t{status}\t{f0}\t{f1}\t{f2}\t{f3}\t{f4}\t{f5}\n"
		).get()
	)
	return 0
