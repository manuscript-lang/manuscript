import (
	StringBuilder from "@std/string_builder.ms",
	Instant, monotonic from "@std/time.ms",
)

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn report(name: String, t0: Instant, sum: Int) Unit:
	ns := monotonic().difference(t0).to_nanoseconds()
	print("{name} {ns / 1000000} ms {sum}")

fn main() Unit:
	n := 1000000
	var x = 7
	var words: List[String] = []

	for i in 0..n:
		x = lcg(x)
		words.append("w{x % 100000}-{x / 7 % 977}")

	text := words.join(" ")
	var t = monotonic()
	var s = 0
	var i = 0

	while i < 2000000:
		s += text.get(i).length()
		i += 1

	report("get_index", t, s)
	t = monotonic()
	s = 0
	for k in 0..1000000: s += text.slice(k, k + 5).get("").length()
	report("slice", t, s)
	t = monotonic()
	s = 0
	for w in words: s += w.take(3).length() + w.drop(2).length()
	report("take_drop", t, s)
	t = monotonic()

	var acc = ""
	for k in 0..200000: acc += "x"
	report("append_lit", t, acc.length())
	t = monotonic()

	var sb = StringBuilder()
	for w in words: sb.append(w)
	report("sb_append", t, sb.build().length())
	t = monotonic()
	s = 0
	for k in 0..200: s += text.index_of("w99999-976 w0").get(-1)
	report("index_of_big", t, s)
	t = monotonic()
	s = 0
	for k in 0..200:
		if text.contains("zzzz"): s += 1
	report("contains_miss_big", t, s)
	t = monotonic()
	s = text.split("  ").length() + text.split("-9").length()
	report("split_multi", t, s)
	t = monotonic()
	s = text.fields().length()
	report("fields", t, s)
	t = monotonic()
	s = text.replace("w9", "<>").length() + text.replace("-", "").length()
	report("replace_misc", t, s)
	t = monotonic()
	s = text.upper().length() + text.lower().length()
	report("case_big", t, s)
	t = monotonic()
	s = 0
	for w in words: s += w.trim_chars("w").length()
	report("trim_chars", t, s)
	t = monotonic()
	s = 0
	for w in words: s += w.pad_start(14, "0").length()
	report("pad", t, s)
	t = monotonic()

	sorted := words.sorted(fn a, b: a.compare(b))
	report("sort_strings", t, sorted[0].length())
	t = monotonic()
	s = 0
	for k in 1..words.length():
		if words[k] < words[k - 1]: s += 1
	report("less_than", t, s)
	t = monotonic()

	var nums: List[Int] = []
	for k in 0..n: nums.append(k * 7)
	s = nums.map(fn v: v.to_string()).join(",").length()
	report("join_ints", t, s)
