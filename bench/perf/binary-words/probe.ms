import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	panic from "@std/core.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	monotonic from "@std/time.ms",
)

fn work_i8(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int8,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int8(start + i * 1)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int8(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int8(data.int8(start + i * 1).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i8(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_int8().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i8(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i8(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u8(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt8,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint8(start + i * 1)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append(data.uint8(start + i * 1).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u8(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_uint8().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u8(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u8(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i16le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int16,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int16_le(start + i * 2)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int16_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int16_le(data.int16_le(start + i * 2).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i16le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_int16().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i16le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i16le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i16be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int16,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int16_be(start + i * 2)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int16_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int16_be(data.int16_be(start + i * 2).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i16be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_int16().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i16be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i16be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u16le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt16,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint16_le(start + i * 2)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint16_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint16_le(data.uint16_le(start + i * 2).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u16le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_uint16().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u16le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u16le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u16be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt16,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint16_be(start + i * 2)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint16_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint16_be(data.uint16_be(start + i * 2).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u16be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_uint16().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u16be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u16be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i32le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int32_le(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int32_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int32_le(data.int32_le(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i32le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_int32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i32le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i32le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i32be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int32_be(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int32_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int32_be(data.int32_be(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i32be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_int32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i32be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i32be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u32le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint32_le(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint32_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint32_le(data.uint32_le(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u32le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_uint32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u32le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u32le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u32be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint32_be(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint32_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint32_be(data.uint32_be(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u32be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get().to_uint32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u32be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u32be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i64le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int64_le(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int64_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int64_le(data.int64_le(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i64le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i64le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i64le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_i64be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Int,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.int64_be(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_int64_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_int64_be(data.int64_be(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_i64be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_int().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_i64be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_i64be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u64le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt64,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint64_le(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint64_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint64_le(data.uint64_le(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u64le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	parts := args[7].split(":")
	want := (
		parts[0].parse_int().get().to_uint64().get(0) * 4294967296
		+ parts[1].parse_int().get().to_uint64().get(0)
	)
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u64le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u64le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_u64be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: UInt64,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.uint64_be(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_uint64_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_uint64_be(data.uint64_be(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_u64be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	parts := args[7].split(":")
	want := (
		parts[0].parse_int().get().to_uint64().get(0) * 4294967296
		+ parts[1].parse_int().get().to_uint64().get(0)
	)
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_u64be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_u64be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_f32le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Float32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.float32_le(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_float32_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_float32_le(data.float32_le(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_f32le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_float().get().to_float32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_f32le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_f32le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_f32be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Float32,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.float32_be(start + i * 4)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_float32_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_float32_be(data.float32_be(start + i * 4).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_f32be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_float().get().to_float32().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_f32be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_f32be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_f64le(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Float,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.float64_le(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_float64_le(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_float64_le(data.float64_le(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_f64le(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_float().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_f64le(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_f64le(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn work_f64be(
	op: String,
	data: Bytes,
	expected: Bytes,
	start: Int,
	fields: Int,
	count: Int,
	want: Float,
	kind: String,
) Int:
	var checksum = 0

	if op == "read":
		for unused in 0..count:
			for i in 0..fields:
				got := data.float64_be(start + i * 8)

				if kind == "OK":
					if got.get() != want: panic("wrong value")
				else:
					if got.is_ok(): panic("expected error")
					if (
						got.err().kind != kind
						or got.err().message != "binary: value out of range"
					): panic("wrong error")

				checksum += 1

		return checksum

	if op == "pack":
		for unused in 0..count:
			var out = BytesBuilder()
			for i in 0..fields:
				out.append_float64_be(want)

			actual := out.build()
			if actual != expected: panic("wrong output")
			checksum += actual.length() + 1

		return checksum

	for unused in 0..count:
		var out = BytesBuilder()
		for i in 0..fields:
			out.append_float64_be(data.float64_be(start + i * 8).get())

		actual := out.build()
		if actual != expected: panic("wrong output")
		checksum += actual.length() + 1

	return checksum

fn launch_f64be(args: List[String]) Int:
	op := args[0]
	data := read_file(args[2]).wait().get()
	expected := read_file(args[3]).wait().get()
	start := args[4].parse_int().get()
	fields := args[5].parse_int().get()
	count := args[6].parse_int().get()
	want := args[7].parse_float().get()
	kind := args[8]
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := work_f64be(op, data, expected, start, fields, warm, want, kind)
	begin := monotonic()
	checksum := work_f64be(op, data, expected, start, fields, count, want, kind)
	elapsed := monotonic().difference(begin).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

export fn main() Int:
	args := arguments()

	match args[1]:
		"i8": return launch_i8(args)
		"u8": return launch_u8(args)
		"i16le": return launch_i16le(args)
		"i16be": return launch_i16be(args)
		"u16le": return launch_u16le(args)
		"u16be": return launch_u16be(args)
		"i32le": return launch_i32le(args)
		"i32be": return launch_i32be(args)
		"u32le": return launch_u32le(args)
		"u32be": return launch_u32be(args)
		"i64le": return launch_i64le(args)
		"i64be": return launch_i64be(args)
		"u64le": return launch_u64le(args)
		"u64be": return launch_u64be(args)
		"f32le": return launch_f32le(args)
		"f32be": return launch_f32be(args)
		"f64le": return launch_f64le(args)
		"f64be": return launch_f64be(args)
		_: return 2
