// expect-debug: allocs=3 alloc_bytes=152
// expect-release: allocs=3 alloc_bytes=152
// A trim whose result is only read in place makes no string: the view twin answers
// bytes of the receiver, so a thousand calls allocate what the receiver cost and
// nothing more.
fn width(s String) Int {
	return s.trim().length() + s.trim_start().length() + s.trim_end().length()
}

export fn main() Int {
	s := f"   padded text that is longer than the inline limit {1}   "
	var n = 0
	for i in 0..1000 {
		n += width(s)
	}
	return if n > 0 { 0 } else { 1 }
}
