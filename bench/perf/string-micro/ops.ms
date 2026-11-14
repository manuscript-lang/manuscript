import (
	arguments from "@std/os/env.ms",
	monotonic, Instant from "@std/time.ms",
)

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn report(name: String, t0: Instant, n: Int, sum: Int) Unit:
	ns := monotonic().difference(t0).to_nanoseconds()
	print("{name} {ns / 1000000} ms {sum}")

fn main() Unit:
	n := 1000000
	var x = 7
	var words: List[String] = []
	for i in 0..n:
		x = lcg(x)
		words.append("w{x % 100000}-{x / 7 % 977}")
	var nums: List[String] = []
	for i in 0..n:
		x = lcg(x)
		nums.append((x % 1000000007).to_string())

	var t = monotonic()
	var s = 0
	for w in nums: s += w.parse_int().get(0)
	report("parse_int", t, n, s)

	t = monotonic()
	s = 0
	for i in 0..n: s += (i * 31).to_string().length()
	report("int_to_string", t, n, s)

	t = monotonic()
	s = 0
	for i in 0..n: s += "a{i}:{i * 3}b".length()
	report("interp", t, n, s)

	t = monotonic()
	s = 0
	for w in words:
		if w.starts_with("w9"): s += 1
	report("starts_with", t, n, s)

	t = monotonic()
	s = 0
	for w in words:
		for c in w.chars(): s += c.length()
	report("scalars_iter", t, n, s)

	t = monotonic()
	s = 0
	for w in words: s += w.split("-").length()
	report("split_small", t, n, s)

	line := words.join(",")
	t = monotonic()
	s = line.split(",").length()
	report("split_big", t, n, s)

	t = monotonic()
	s = words.join(" ").length()
	report("join", t, n, s)

	t = monotonic()
	s = line.replace(",", ";;").length()
	report("replace_big", t, n, s)

	t = monotonic()
	s = 0
	for w in words: s += w.upper().length()
	report("upper", t, n, s)

	t = monotonic()
	s = 0
	for w in words: s += w.reverse().length()
	report("reverse", t, n, s)

	t = monotonic()
	s = 0
	for w in words: s += w.repeat(3).get("").length()
	report("repeat", t, n, s)

	t = monotonic()
	s = 0
	for w in words:
		if w == "w5-5": s += 1
	report("equal", t, n, s)

	t = monotonic()
	s = line.lines().length()
	report("lines", t, n, s)

	t = monotonic()
	s = 0
	for w in words: s += w.hash() % 7
	report("hash", t, n, s)

	t = monotonic()
	s = 0
	for i in 0..n: s += (i.to_float() * 1.37).to_string().length()
	report("float_to_string", t, n, s)

	t = monotonic()
	s = 0
	for i in 0..n: s += (i.to_float() * 1.37).to_string().parse_float().get(0.0).truncate_to_int().get(0)
	report("float_parse", t, n, s)
