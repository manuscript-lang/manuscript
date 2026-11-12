import (
	arguments from "@std/os/env.ms",
	posix, win32 from "@std/os/path.ms",
	monotonic from "@std/time.ms",
)

fn main() Unit!:
	args := arguments()
	kind := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	var parts: List[String] = []
	for i in 0..n:
		parts.append(if kind == "dots": "a/../é🙂" else: "segment")
	if kind == "absolute": parts.append("/reset/end/")
	if kind == "invalid": parts.append("bad\u{0}path")

	paths := if kind == "windows": win32() else: posix()
	base := if kind == "windows": "C:\\base" else: "/base/"
	expected := paths.resolve(base, parts)
	var checksum = 0
	start := monotonic()

	for unused in 0..repeats:
		out := paths.resolve(base, parts)
		if out != expected: return error(Error("unequal output"))

		if value := out:
			checksum += value.byte_length()
		else:
			checksum += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checksum}")
