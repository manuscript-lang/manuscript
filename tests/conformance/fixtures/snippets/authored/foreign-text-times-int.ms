// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn main() Void {
	line := "-" * 20
	print(line)
}
// expect-error: MS3001 5:17 operator operands require the same independently known type, found String * Int; to repeat text write text.repeat(count), which returns a String
