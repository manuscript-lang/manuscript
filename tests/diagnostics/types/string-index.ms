// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	word := "abc"
	first := word[0]
	return 0
}
// expect-error: MS3000 5:14 indexing a String by integer is not supported; use for c in s.chars(), s.scalar_at(offset, default) at a byte offset, or s.slice(start, end)
