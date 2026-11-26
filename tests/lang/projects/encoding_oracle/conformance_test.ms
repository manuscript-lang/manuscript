import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Base32Options,
	ascii85_decode,
	ascii85_encode,
	base32_decode,
	base32_encode,
	base64_decode,
	base64_encode,
	hex_decode,
	hex_encode from "@std/data/encoding.ms",
	fail from "@std/test/test.ms",

	files from "@oracle",
)

// Replays data/encoding.tsv, the corpus recorded from the C natives behind
// `@std/data/encoding`: one case per line as `operation<TAB>inputs...<TAB>=><TAB>outcome`.
// Bytes and text are `x` and the hex of their bytes, `-` is no limit, and an error is
// `err` and its kind. The test reads hex with its own parser, so the codec under test
// never decodes its own inputs.

fn nibble(c Int) Int {
	if c >= 48 and c <= 57 { return c - 48 }
	return c - 87
}

fn raw(token String) Bytes {
	if token == "-" { return "".to_bytes() }

	digits := token.to_bytes()
	var out = BytesBuilder()
	var i = 1

	while i + 1 < digits.length() {
		out.append(
			(
				nibble(digits.get(i).to_int()) * 16
				+ nibble(digits.get(i + 1).to_int())
			).to_uint8() or 0
		)
		i += 2
	}

	return out.build()
}

fn text(token String) String {
	return raw(token).decode_utf8() or ""
}

fn hex(value Bytes) String {
	digits := "0123456789abcdef"
	var out = "x"

	for i in 0..value.length() {
		b := value.get(i).to_int()
		out += digits.view(b / 16, b / 16 + 1)
		out += digits.view(b % 16, b % 16 + 1)
	}

	return out
}

fn limit(token String) Int? {
	if token == "-" { return null }
	return token.parse_int() or 0
}

fn outcome(result Bytes!) String {
	if result.is_error() { return f"err {result.err().kind}" }
	return f"ok {hex(result.get_or("".to_bytes()))}"
}

fn answer(f List[String]) String {
	op := f[0]

	if op == "enc64" {
		v := f[1].parse_int() or 0
		return f"ok {hex(base64_encode(raw(f[2]), v / 2 == 1, v % 2 == 1).to_bytes())}"
	}

	if op == "enc32" {
		v := f[1].parse_int() or 0
		return f"ok {hex(base32_encode(raw(f[2]), Base32Options(v / 2 == 1, v % 2 == 1)).to_bytes())}"
	}

	if op == "ench" { return f"ok {hex(hex_encode(raw(f[1])).to_bytes())}" }
	if op == "enc85" { return f"ok {hex(ascii85_encode(raw(f[1])).to_bytes())}" }
	if op == "dec64" {
		return outcome(base64_decode(text(f[4]), f[1] == "1", f[2] == "1", limit(f[3])))
	}
	if op == "dec32" {
		return outcome(
			base32_decode(
				text(f[4]),
				Base32Options(f[1] == "1", f[2] == "1"),
				limit(f[3]),
			)
		)
	}
	if op == "dech" { return outcome(hex_decode(text(f[2]), limit(f[1]))) }
	if op == "dec85" { return outcome(ascii85_decode(text(f[2]), limit(f[1]))) }

	return f"unknown case {op}"
}

test "encoding operations match the recorded corpus" {
	raw := files().read("encoding.tsv", null).get_or("".to_bytes())
	data := raw.decode_utf8() or ""
	var checked = 0
	var failures = List[String]()

	for line in data.split("\n") {
		if line.is_empty() or line.starts_with("#") { continue }

		f := line.split("\t").collect()
		got := answer(f)
		checked += 1
		if got != f[f.length() - 1] and failures.length() < 10 {
			failures.append(f"{line} -> {got}")
		}
	}

	if not failures.is_empty() {
		return fail(f"{failures.length()} mismatches, first:\n{failures.join("\n")}")
	}
	if checked < 7000 { return fail(f"only {checked} cases replayed") }

	return ok()
}
