// expect-debug: allocs=1003 alloc_bytes=256179
// expect-release: allocs=1003 alloc_bytes=256179
// `fields` is declared `List[&String]`: each field views the text in place and the list is
// sized once, so a call is one allocation (plus the text).
export fn main() Int {
	text := f"alpha beta gamma delta  epsilon zeta eta theta iota kappa lambda mu nu xi omicron {7}"
	var n = 0
	for i in 0..1000 {
		n += text.fields().length() + i - i
	}
	return n % 100
}
