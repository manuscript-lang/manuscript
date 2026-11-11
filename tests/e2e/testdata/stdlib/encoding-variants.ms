import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Base32Options,
	base32_decode,
	base32_encode,
	base64_decode,
	base64_encode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

test "unpadded Base64 covers both alphabets and every tail":
	texts := ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
	encoded := ["", "Zg", "Zm8", "Zm9v", "Zm9vYg", "Zm9vYmE", "Zm9vYmFy"]

	for index in 0..texts.length():
		for url_safe in [false, true]:
			expect_equal(
				base64_encode(
					texts[index].to_bytes(), url_safe, padded: false
				),
				encoded[index]
			)?
			expect_equal(
				base64_decode(encoded[index], url_safe, padded: false)?,
				texts[index].to_bytes()
			)?

	bytes := Bytes([251, 255])
	expect_equal(base64_encode(bytes, padded: false), "+/8")?
	expect_equal(base64_encode(bytes, true, padded: false), "-_8")?
	expect_equal(base64_decode("-_8", true, padded: false)?, bytes)?

test "unpadded Base64 rejects padding alphabet mixing whitespace and unused bits":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	for text in [
		"A", "AAAAA", "Zg=", "Zg==", "=Zg", "Zh", "Zm9", "Z g", "Zg\n", "Zg\r", "Zg\t",
		"é", "!!!!"
	]:
		expect_equal(base64_decode(text, padded: false), invalid)?
	expect_equal(base64_decode("-_8", padded: false), invalid)?
	expect_equal(base64_decode("+/8", true, padded: false), invalid)?

test "Base32 matches RFC 4648 padded and unpadded vectors":
	texts := ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
	encoded := [
		"", "MY======", "MZXQ====", "MZXW6===", "MZXW6YQ=", "MZXW6YTB",
		"MZXW6YTBOI======"
	]
	raw := ["", "MY", "MZXQ", "MZXW6", "MZXW6YQ", "MZXW6YTB", "MZXW6YTBOI"]
	hex := [
		"", "CO======", "CPNG====", "CPNMU===", "CPNMUOG=", "CPNMUOJ1",
		"CPNMUOJ1E8======"
	]
	hex_raw := ["", "CO", "CPNG", "CPNMU", "CPNMUOG", "CPNMUOJ1", "CPNMUOJ1E8"]

	for index in 0..texts.length():
		bytes := texts[index].to_bytes()
		expect_equal(base32_encode(bytes), encoded[index])?
		expect_equal(base32_encode(bytes, Base32Options(padded: false)), raw[index])?
		expect_equal(
			base32_encode(bytes, Base32Options(hex_alphabet: true)), hex[index]
		)?
		expect_equal(
			base32_encode(
				bytes, Base32Options(hex_alphabet: true, padded: false)
			),
			hex_raw[index]
		)?
		expect_equal(base32_decode(encoded[index])?, bytes)?
		expect_equal(base32_decode(raw[index], Base32Options(padded: false))?, bytes)?
		expect_equal(
			base32_decode(hex[index], Base32Options(hex_alphabet: true))?, bytes
		)?
		expect_equal(
			base32_decode(
				hex_raw[index], Base32Options(hex_alphabet: true, padded: false)
			)?,
			bytes
		)?

test "Base32 enforces exact terminal padding and uppercase alphabets":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	for text in [
		"M", "MY", "MY=", "MY=====", "MY=======", "M======", "MZX=====", "MZXW6Y==",
		"========", "MY======MY======", "M=AAAAAA", "my======", "M0======", "M1======",
		"M8======", "M9======", "MY=====\n", "M Y=====", "éY======"
	]:
		expect_equal(base32_decode(text), invalid)?
	for text in [
		"M", "MZX", "MZXW6Y", "MY=", "MY======", "my", "M0", "M1", "M8", "M9", "MY\r\n"
	]:
		expect_equal(base32_decode(text, Base32Options(padded: false)), invalid)?
	expect_equal(base32_decode("W0======", Base32Options(hex_alphabet: true)), invalid)?
	expect_equal(base32_decode("CO======"), invalid)?

test "Base32 rejects nonzero unused bits in each tail shape":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	for text in ["MZ======", "MZX R===", "MZXR====", "MZXW7===", "MZXW6YR="]:
		expect_equal(base32_decode(text), invalid)?
	for text in ["MZ", "MZXR", "MZXW7", "MZXW6YR"]:
		expect_equal(base32_decode(text, Base32Options(padded: false)), invalid)?
	for text in ["CP======", "CPNH====", "CPNMV===", "CPNMUOH="]:
		expect_equal(base32_decode(text, Base32Options(hex_alphabet: true)), invalid)?

test "encoding variants honor zero exact exceeded absent and negative limits":
	empty := Bytes([])
	invalid: Bytes! := error(Error("encoding: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(base32_decode("", max_bytes: 0)?, empty)?
	expect_equal(base64_decode("", max_bytes: 0, padded: false)?, empty)?
	expect_equal(base32_decode("MY======", max_bytes: 1)?, "f".to_bytes())?
	expect_equal(
		base32_decode("MY", Base32Options(padded: false), max_bytes: 1)?, "f".to_bytes()
	)?
	expect_equal(base32_decode("MY======", max_bytes: 0), limited)?
	expect_equal(base64_decode("Zg", max_bytes: 0, padded: false), limited)?
	expect_equal(base64_decode("Zg", max_bytes: 1, padded: false)?, "f".to_bytes())?
	expect_equal(base32_decode("MY======", max_bytes: none)?, "f".to_bytes())?
	expect_equal(base64_decode("Zg", max_bytes: none, padded: false)?, "f".to_bytes())?

	for text in ["", "?", "MY======"]:
		expect_equal(base32_decode(text, max_bytes: -1), invalid)?
		expect_equal(base64_decode(text, max_bytes: -1, padded: false), invalid)?

test "encoding variants honor Bytes views and cross block boundaries":
	var out = BytesBuilder()
	for value in 0..256: out.append(value.to_uint8().get(0))

	all := out.build()

	for length in 0..256:
		bytes := all.slice(0, length)?
		for hex in [false, true]:
			for padded in [false, true]:
				expect_equal(
					base32_decode(
						base32_encode(
							bytes,
							Base32Options(
								hex_alphabet: hex, padded: padded
							)
						),
						Base32Options(
							hex_alphabet: hex, padded: padded
						),
						length
					)?,
					bytes
				)?
		for url in [false, true]:
			expect_equal(
				base64_decode(
					base64_encode(bytes, url, padded: false), url, length, padded: false
				)?,
				bytes
			)?

	view := all.slice(17, 219)?
	expect_equal(base32_decode(base32_encode(view))?, view)?
	expect_equal(
		base64_decode(base64_encode(view, padded: false), padded: false)?, view
	)?

test "encoding variant function values retain defaults":
	encode := base32_encode
	decode := base32_decode
	expect_equal(encode("f".to_bytes()), "MY======")?
	expect_equal(decode("MY======")?, "f".to_bytes())?

	raw_encode := base64_encode
	raw_decode := base64_decode
	expect_equal(raw_encode("f".to_bytes()), "Zg==")?
	expect_equal(raw_decode("Zg==")?, "f".to_bytes())?
	expect_equal(raw_encode("f".to_bytes(), padded: false), "Zg")?

test "Base32 rejects interior padding before output budgets":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	negative: Bytes! := error(Error("encoding: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))

	for hex in [false, true]:
		for text in ["A=AAAAAA", "AA======AA======"]:
			expect_equal(
				base32_decode(
					text, Base32Options(hex_alphabet: hex, padded: true), 0
				),
				invalid
			)?
			expect_equal(
				base32_decode(
					text, Base32Options(hex_alphabet: hex, padded: true), -1
				),
				negative
			)?
			expect_equal(
				base32_decode(
					text, Base32Options(hex_alphabet: hex, padded: true)
				),
				invalid
			)?
			expect_equal(
				base32_decode(
					text, Base32Options(hex_alphabet: hex, padded: true), 100
				),
				invalid
			)?

		expect_equal(
			base32_decode(
				"A=AA", Base32Options(hex_alphabet: hex, padded: false), 0
			),
			invalid
		)?
		expect_equal(
			base32_decode(
				"A=AA", Base32Options(hex_alphabet: hex, padded: false), 100
			),
			invalid
		)?
		expect_equal(
			base32_decode(
				"!!!!!!!!", Base32Options(hex_alphabet: hex, padded: true), 0
			),
			limited
		)?
		expect_equal(
			base32_decode(
				"!!!!!!!!", Base32Options(hex_alphabet: hex, padded: true), 100
			),
			invalid
		)?

	expect_equal(base64_decode("A=AA", max_bytes: 0, padded: false), limited)?

test "unpadded Base64 preserves byte budget precedence for invalid padding":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	negative: Bytes! := error(Error("encoding: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))

	for url in [false, true]:
		for text in ["AA==", "AAA=", "===="]:
			for budget in 0..3:
				expect_equal(base64_decode(text, url, budget, padded: false), limited)?
			expect_equal(base64_decode(text, url, 3, padded: false), invalid)?
			expect_equal(base64_decode(text, url, -1, padded: false), negative)?

		expect_equal(base64_decode("A", url, 0, padded: false), invalid)?
		expect_equal(base64_decode("!!!!", url, 0, padded: false), limited)?
		expect_equal(base64_decode("!!!!", url, 3, padded: false), invalid)?

	expect_equal(base64_decode("Zg", max_bytes: 1, padded: false)?, "f".to_bytes())?
