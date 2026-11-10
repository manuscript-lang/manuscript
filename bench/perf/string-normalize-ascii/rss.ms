import stdout from "@std/io/io.ms"

fn main() Int:
	text := "x".repeat(4194304).get()
	result := text.normalize("NFC").get()
	if result != text: return 1

	_written := stdout().write("{result.byte_length()}\n")
	return 0
