// conform: tags=diagnostics,numbers,faults,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	return [1, 2][-3]
}
// expect-error: MS3070 5:12 index -3 is outside this list literal of 2 element(s) and always faults
