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
	var longs List[String] = []

	for i in 0..n {
		x = lcg(x)
		words.append(f"w{x % 100000}-{x / 7 % 977}")
		longs.append(f"/usr/share/lib/module-{x % 100000}/file-{x / 7 % 977}.txt")
	}

	text := words.join(" ")
	var t = monotonic()
	var s = 0

	// word frequency: string-keyed map, short (inline) keys
	t = monotonic()

	var freq Map[String, Int] = Map[String, Int]()
	for w in words { freq.update(w.clone(), 0, v => v + 1) }
	report("freq_short", t, freq.length())

	// string-keyed map, heap keys
	t = monotonic()

	var freq2 Map[String, Int] = Map[String, Int]()
	for w in longs { freq2.update(w.clone(), 0, v => v + 1) }
	report("freq_long", t, freq2.length())

	// lookups
	t = monotonic()
	s = 0
	for w in longs {
		if freq2.contains(w) { s += 1 }
	}
	report("lookup_long", t, s)

	// char scan: count digits and spaces in a large text
	t = monotonic()
	s = 0

	for c in text.chars() {
		if c >= "0" and c <= "9" {
			s += 1
		} else if c == " " {
			s += 100
		}
	}

	report("chars_scan", t, s)

	// bytes scan
	t = monotonic()
	s = 0

	bytes := text.as_bytes()
	for i in 0..bytes.length() {
		if bytes.get_or(i, 0) == 32 { s += 1 }
	}
	report("bytes_scan", t, s)

	// non-ASCII text
	utext := text.replace("w", "é")
	t = monotonic()
	s = 0
	for c in utext.chars() {
		if c == "é" { s += 1 }
	}
	report("chars_scan_utf8", t, s)
	t = monotonic()

	at := utext.index_of("é99999")
	before := if at != null {
		utext.view(0, at or 0).scalar_length()
	} else {
		-1
	}
	s = utext.scalar_length() + before + utext.count("é1")
	report("utf8_len_index_count", t, s)
	t = monotonic()
	s = 0

	var offset = 0

	while offset < utext.length() {
		code := utext.scalar_at(offset, 0)
		s += code
		offset += (
			if code < 128 { 1 } else { if code < 2048 { 2 } else { if code < 65536 { 3 } else { 4 } } }
		)
	}

	report("utf8_offset_walk", t, s)
	t = monotonic()
	s = utext.upper().scalar_length() + utext.reverse().scalar_length()
	report("utf8_case_reverse", t, s)

	// per-word ops
	t = monotonic()
	s = 0
	for w in longs {
		if w.ends_with(".txt") and w.starts_with("/usr") { s += 1 }
	}
	report("starts_ends_long", t, s)
	t = monotonic()
	s = 0
	for w in longs {
		if w.contains("file-9") { s += 1 }
	}
	report("contains_short", t, s)
	t = monotonic()
	s = 0
	for w in longs { s += (w.index_of("module") or 0) + (w.last_index_of("/") or 0) }
	report("index_of_small", t, s)
	t = monotonic()
	s = 0
	for w in longs { s += w.split("/").length() }
	report("split_path", t, s)
	t = monotonic()
	s = 0
	for w in longs { s += w.replace("file", "f").length() }
	report("replace_small", t, s)
	t = monotonic()
	s = 0
	for w in longs { s += w.lower().length() }
	report("lower_small", t, s)
	t = monotonic()
	s = 0
	for w in longs { s += w.trim().length() }
	report("trim_small", t, s)

	// concat/format
	t = monotonic()
	s = 0
	for i in 0..n { s += (words[i] + "/" + longs[i]).length() }
	report("concat3", t, s)
	t = monotonic()
	s = 0
	for i in 0..n { s += f"{words[i]}={longs[i]};".length() }
	report("interp_strings", t, s)
	t = monotonic()

	var sb = ""

	for i in 0..n {
		sb += words[i]
		sb += ","
		sb += i.to_string()
		sb += "\n"
	}

	report("builder_mixed", t, sb.length())
	t = monotonic()

	var acc = ""
	for i in 0..n { acc += words[i] }
	report("plus_equals", t, acc.length())

	// equality and comparison of long same-length strings
	t = monotonic()
	s = 0
	for i in 1..n {
		if longs[i] == longs[i - 1] { s += 1 }
	}
	report("eq_long", t, s)

	// conversions
	t = monotonic()
	s = 0
	for i in 0..n { s += (i.to_string_radix(16) or "").length() }
	report("int_hex", t, s)
	t = monotonic()
	s = 0
	for i in 0..n { s += (i.to_float() / 7.0).to_fixed(2).length() }
	report("float_fixed", t, s)
}
