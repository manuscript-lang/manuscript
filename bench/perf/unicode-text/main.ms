// String.upper, lower and normalize over five kinds of text, 64 KiB each, ns per input
// byte.
// `ms run bench/perf/unicode-text/main.ms -- 200`: passes over each text per case.
// Prints one line per case with a checksum of the result lengths; the same text must
// print the same checksum on every build (the Rust runtime before the C tables, the C
// runtime after).
import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

// Name, unit text and a form to run; the unit repeats to about 64 KiB.
fn texts() List[List[String]]:
	return [
		["ascii", "The quick brown fox jumps over the lazy dog 0123456789. "],
		[
			"latin", "Crème brûlée à la façon de l'été, naïve café, Zürich Škoda Łódź. "
		],
		["greek", "Οδυσσεύς ὁ πολύτροπος ΣΟΦΟΣ ἀγαθός ᾅδης καὶ ΠΟΛΥΤΡΟΠΟΣ. "],
		["cjk", "漢字かな交じり文を正規化する。한국어 텍스트 각 한글 ﬁ①. "],
		[
			"marks",
			"Cre\u{300}me bru\u{302}le\u{301}e a\u{300} Zu\u{308}rich Sa\u{323}\u{307}o. "
		],
	]

fn repeat_to(unit: String, target: Int) String:
	return unit.repeat(target / unit.length() + 1)

fn run_case(label: String, text: String, passes: Int, step: fn(String) Int) Void:
	var total = 0
	t0 := monotonic()
	for _pass in 0..passes: total += step(text)

	t1 := monotonic()
	ns := t1.difference(t0).to_nanoseconds()
	print(
		f"{label}: {ns * 100 / (passes * text.length())} ns/100 bytes, checksum {total}"
	)

fn normalized(text: String, form: String) Int:
	return text.normalize(form, none).get().length()

fn main() Void:
	passes := arguments()[0].parse_int().get()

	for entry in texts():
		text := repeat_to(entry[1], 65536)
		name := entry[0]
		run_case(f"{name} upper", text, passes, fn t: t.upper().length())
		run_case(f"{name} lower", text, passes, fn t: t.lower().length())
		run_case(f"{name} NFC", text, passes, fn t: normalized(t, "NFC"))
		run_case(f"{name} NFD", text, passes, fn t: normalized(t, "NFD"))
		run_case(f"{name} NFKC", text, passes, fn t: normalized(t, "NFKC"))
		run_case(f"{name} NFKD", text, passes, fn t: normalized(t, "NFKD"))
