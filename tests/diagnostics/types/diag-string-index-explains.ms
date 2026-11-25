// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	s := "abc"
	c := s[0]
}
// expect-error: MS3000 6:10 indexing a String by integer is not supported; use for c in s.chars(), s.scalar_at(offset, default) at a byte offset, or s.slice(start, end)
