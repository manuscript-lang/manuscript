import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn text(word: String) String:
	var out = StringBuilder()
	out.append(word)
	out.append("!")
	return out.build()

fn packed() Bytes:
	var out = BytesBuilder()
	out.append(65)
	out.append_bytes(Bytes([66, 67]))
	return out.build()

fn empty() Bytes:
	return Bytes([])

fn main() Int:
	return text("a").length() + packed().length() + empty().length() - 5
