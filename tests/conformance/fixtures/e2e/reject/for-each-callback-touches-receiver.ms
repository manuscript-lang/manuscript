// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void {
	var xs = [1, 2]
	xs.for_each((var n) => xs.append(n))
}
// expect-error: MS3000 5:8 the receiver `xs` of `for_each` is moved or changed in place but overlaps the closure at 5:17; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
