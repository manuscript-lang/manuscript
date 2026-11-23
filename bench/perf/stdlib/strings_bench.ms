import words from "./src/harness.ms"

type BenchData:
	text: String
	text_5: String
	text_6: String
	text_7: String
	text_9: String
	text_10: String

fn make_fixture() BenchData:
	text := words(2000).join(" ")
	text_5 := words(2000).join(" ")
	text_6 := words(2000).join(" ")
	text_7 := words(2000).join(" ")
	text_9 := words(2000).join(" ")
	text_10 := words(2000).join(" ")
	return BenchData(
		text: text,
		text_5: text_5,
		text_6: text_6,
		text_7: text_7,
		text_9: text_9,
		text_10: text_10,
	)

bench "string.append_builder" per 100000:
	var sb = ""
	for i in 0..100000:
		sb += "x"
	sb.length()

bench "string.concat" per 20000:
	var s = ""
	for i in 0..20000:
		s = s.concat("x")
	s.length()

bench "string.append_interpolated" per 20000:
	var s = ""
	for i in 0..20000:
		s += f"item-{i},"
	s.length()

bench "string.split" per 200:
	var n = 0
	for i in 0..200:
		n += fixture.text.split(" ").length()
	n

bench "string.replace" per 200:
	var n = 0
	for i in 0..200:
		n = (n + fixture.text_5.replace("word", "w").length())
	n

bench "string.contains" per 2000:
	var n = 0
	for i in 0..2000:
		if fixture.text_6.contains("word976 word0"): n += 1
	n

bench "string.upper" per 200:
	var n = 0
	for i in 0..200:
		n += fixture.text_7.upper().length()
	n

bench "string.trim" per 100000:
	var n = 0
	for i in 0..100000:
		n += "  padded  ".trim().length()
	n

bench "string.index_char_at" per 100000:
	var n = 0
	for i in 0..100000:
		n += fixture.text_9.scalar_at(i % 5000, 0)
	n

bench "string.chars" per 20:
	var n = 0
	for i in 0..20:
		n += fixture.text_10.chars().length()
	n

bench "string.parse_int" per 100000:
	var n = 0
	for i in 0..100000:
		n += "12345".parse_int().get_or(0)
	n

bench "string.interpolate" per 100000:
	var n = 0
	for i in 0..100000:
		n += f"item {i} of {n}".length()
	n
