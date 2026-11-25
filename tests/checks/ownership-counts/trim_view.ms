// expect-debug: allocs=3 alloc_bytes=155
// expect-release: allocs=3 alloc_bytes=155
// `trim`, `trim_start` and `trim_end` borrow the receiver, so measuring or comparing a trimmed
// text copies nothing: the three allocations are the one padded text, built once.
fn width(s String) Int {
	return s.trim().length() + s.trim_start().length() + s.trim_end().length()
}

export fn main() Int {
	text := f"   padded text that is long enough to live on the heap {1}   "
	var total = 0
	for round in 0..1000 {
		total += width(text) + round - round
	}
	return total - 1000 * (text.length() - 6 + text.length() - 3 + text.length() - 3)
}
