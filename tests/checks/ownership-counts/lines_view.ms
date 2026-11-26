// expect-debug: allocs=1003 alloc_bytes=64196
// expect-release: allocs=1003 alloc_bytes=64196
// `lines` is declared `List[&String]`: each line views the text in place and the list is sized
// once, so a call is one allocation, not one per line.
export fn main() Int {
	text := f"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron {7}\nsecond line\nthird"
	var n = 0
	for i in 0..1000 {
		n += text.lines().length() + i - i
	}
	return n % 100
}
