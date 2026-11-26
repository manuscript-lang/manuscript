// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn main() Void {
	xs Vec[Int] := []
	print(xs.length())
}
// expect-error: MS2001 5:8 unknown type Vec; did you mean 'List'?
// expect-fix: 5:8-5:11 "List"
