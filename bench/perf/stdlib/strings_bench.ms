import (
	StringBuilder from "@std/string_builder.ms",
	keep, measure from "@std/test/bench.ms",

	words from "./src/harness.ms",
)

bench "string.append_builder":
	fn work() Result[Unit, Error]:
		var sb = StringBuilder()
		for i in 0..100000:
			sb.append("x")
		return keep(sb.build().byte_length())

	measure(100000, work)?

bench "string.concat":
	fn work() Result[Unit, Error]:
		var s = ""
		for i in 0..20000:
			s = s.concat("x")
		return keep(s.length())

	measure(20000, work)?

bench "string.append_interpolated":
	fn work() Result[Unit, Error]:
		var s = ""
		for i in 0..20000:
			s += "item-{i},"
		return keep(s.length())

	measure(20000, work)?

bench "string.split":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..200:
			n += text.split(" ").length()
		return keep(n)

	measure(200, work)?

bench "string.replace":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..200:
			n = (n + text.replace("word", "w").length())
		return keep(n)

	measure(200, work)?

bench "string.contains":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..2000:
			if text.contains("word976 word0"): n += 1
		return keep(n)

	measure(2000, work)?

bench "string.upper":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..200:
			n += text.upper().length()
		return keep(n)

	measure(200, work)?

bench "string.trim":
	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..100000:
			n += "  padded  ".trim().length()
		return keep(n)

	measure(100000, work)?

bench "string.index_char_at":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..100000:
			n += text.get(i % 5000, default: "").length()
		return keep(n)

	measure(100000, work)?

bench "string.chars":
	text := words(2000).join(" ")

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..20:
			n += text.chars().length()
		return keep(n)

	measure(20, work)?

bench "string.parse_int":
	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..100000:
			n += "12345".parse_int().get(0)
		return keep(n)

	measure(100000, work)?

bench "string.interpolate":
	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..100000:
			n += "item {i} of {n}".length()
		return keep(n)

	measure(100000, work)?
