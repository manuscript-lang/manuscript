// conform: tags=diagnostics,numbers,faults,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	return 4611686018427387904 * 2
}
// expect-error: MS3000 5:32 4611686018427387904 * 2 overflows Int and always faults; use a smaller value or a wider type such as BigInt
