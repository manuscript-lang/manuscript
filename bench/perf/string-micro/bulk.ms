// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write

import Instant, monotonic from "@std/time.ms"

fn lcg(x Int) Int {
	return (x * 1103515245 + 12345) % 2147483648
}

fn report(name String, t0 Instant, sum Int) Void {
	ns := monotonic().difference(t0).to_nanoseconds()
	print(f"{name} {ns / 1000000} ms {sum}")
}

fn main() Void {
	n := 1000000
	var x = 7
	var words List[String] = []

	for i in 0..n {
		x = lcg(x)
		words.append(f"w{x % 100000}-{x / 7 % 977}")
	}

	text := words.join(" ")
	var t = monotonic()
	var s = 0
	var i = 0

	while i < 2000000 {
		s += text.scalar_at(i, 0)
		i += 1
	}

	report("scalar_at", t, s)
	t = monotonic()
	s = 0
	for k in 0..1000000 { s += text.slice(k, k + 5).length() }
	report("slice", t, s)
	t = monotonic()
	s = 0
	for w in words {
		s += w.view(0, 3).length() + w.view(2, w.length()).length()
	}
	report("take_drop", t, s)
	t = monotonic()

	var acc = ""
	for k in 0..200000 { acc += "x" }
	report("append_lit", t, acc.length())
	t = monotonic()

	var sb = ""
	for w in words { sb += w }
	report("sb_append", t, sb.length())
	t = monotonic()
	s = 0
	for k in 0..200 { s += text.index_of("w99999-976 w0") or (-1) }
	report("index_of_big", t, s)
	t = monotonic()
	s = 0
	for k in 0..200 {
		if text.contains("zzzz") { s += 1 }
	}
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
	for w in words { s += w.trim_chars("w").length() }
	report("trim_chars", t, s)
	t = monotonic()
	s = 0
	for w in words { s += w.pad_start(14, "0").length() }
	report("pad", t, s)
	t = monotonic()

	sorted := words.sorted((a, b) => a.compare(b))
	report("sort_strings", t, sorted[0].length())
	t = monotonic()
	s = 0
	for k in 1..words.length() {
		if words[k] < words[k - 1] { s += 1 }
	}
	report("less_than", t, s)
	t = monotonic()

	var nums List[Int] = []
	for k in 0..n { nums.append(k * 7) }
	s = nums.map(v => v.to_string()).join(",").length()
	report("join_ints", t, s)
}
