import (
	panic from "@std/core.ms",
	parse from "@std/data/xml.ms",
	monotonic from "@std/time.ms",
)

fn measure(name: String, source: String, expected_text: String, count: Int) Unit:
	expected := parse(source).get()
	if expected.text() != expected_text: panic("incorrect expected text")

	var checksum = 0
	start := monotonic()

	for unused in 0..count:
		node := parse(source).get()
		if node != expected: panic("wrong parsed node: {name}")
		checksum += node.children().length() + 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{name},{count},{elapsed},{checksum}")

fn invalid(name: String, source: String, count: Int) Unit:
	var checksum = 0
	start := monotonic()

	for unused in 0..count:
		result := parse(source)
		if result.is_ok(): panic("accepted malformed input")
		if result.err().kind != "EBADMSG": panic("wrong error")
		checksum += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{name},{count},{elapsed},{checksum}")

export fn main() Int:
	measure("empty", "<a/>", "", 100000)
	measure("ordinary", "<a k='v'><b>hello</b></a>", "hello", 30000)
	measure("small-comment", "<a><!--x--></a>", "", 30000)
	measure("small-cdata", "<a><![CDATA[x]]></a>", "x", 30000)
	measure("empty-cdata", "<a><![CDATA[]]></a>", "", 30000)
	measure("empty-instruction", "<?p?><a/>", "", 30000)
	measure("near-delimiter", "<a><![CDATA[]]x]y]]></a>", "]]x]y", 30000)
	measure("empty-attribute", "<a k=''/>", "", 50000)

	for n in [1000, 10000, 100000]:
		text := "é日x".repeat(n / 3).get()
		measure("comment-{n}", "<a><!--{text}--></a>", "", 30)
		measure("cdata-{n}", "<a><![CDATA[{text}]]></a>", text, 30)
		measure("attribute-{n}", "<a k='{text}'/>", "", 30)
		measure("instruction-{n}", "<?p {text}?><a/>", "", 30)
		invalid("missing-close-{n}", "<a><!--{text}", 30)

	invalid("small-invalid", "<a><!--x--", 30000)
	return 0
