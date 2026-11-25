// conform: tags=diagnostics,numbers,faults,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	return -9223372036854775807 - 2
}
// expect-error: MS3000 5:33 -9223372036854775807 - 2 overflows Int and always faults; use a smaller value or a wider type such as BigInt
