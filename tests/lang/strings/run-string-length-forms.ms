// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// The scalar length of inline, heap, flagged and non-ASCII strings agrees on every
// backend.
export fn main() Int {
	inline := "hello"
	inline_wide := "h\u{e9}llo"
	heap_ascii := "plain ascii text that is also longer than fifteen bytes"
	heap_wide := "h\u{e9}llo w\u{f6}rld, this one is long enough to not be inline"
	built := inline + "-" + inline_wide
	print(inline.scalar_length())
	print(inline_wide.scalar_length())
	print(heap_ascii.scalar_length())
	print(heap_wide.scalar_length())
	print(built.scalar_length())
	print("".scalar_length())
	return 0
}
// expect-exit: 0
// expect-stdout: 5
// expect-stdout: 5
// expect-stdout: 55
// expect-stdout: 53
// expect-stdout: 11
// expect-stdout: 0
