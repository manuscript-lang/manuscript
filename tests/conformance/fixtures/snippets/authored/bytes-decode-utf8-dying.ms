// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=bytes-decode-take
// decode_utf8 of a Bytes that is never used again reuses its buffer; every shape must
// decode exactly as the copying call does.
import Bytes from "@std/bytes.ms"

fn decode_last(b: Bytes) String?:
	return b.decode_utf8()

fn decode_twice(b: Bytes) Int:
	first := b.decode_utf8() or ""
	second := b.decode_utf8() or ""
	return first.length() + second.length()

export fn main() Int:
	long := "plain ascii text that is longer than the inline size".to_bytes()
	print(decode_last(long) or "?")
	print(
		decode_last(
			"unicode é🙂 text that is also past the inline size".to_bytes()
		) or "?"
	)
	print(decode_last("short".to_bytes()) or "?")
	print(decode_last("".to_bytes()) or "?")
	print(
		decode_last(
			"abcdefghijklmnopqrstuvwxyz0123456789".to_bytes().view(2, 30)
		) or "?"
	)
	print(decode_twice("kept and decoded twice, longer than inline".to_bytes()))

	text := (
		"owned long enough to be a heap string, grown in place".to_bytes().decode_utf8()
		or ""
	)
	print(text + "!" + text)

	var total = 0
	for i in 0..1000:
		total += (
			f"row {i} with enough text to leave the inline form"
			.to_bytes()
			.decode_utf8()
			or ""
		).length()
	print(total)
	return 0
