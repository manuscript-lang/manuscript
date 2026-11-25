// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	insert := [1].insert
	insert(index: 5, value: 9)
	return 0
}
// expect-error: MS3000 4:19 a method value that changes its receiver must come from a variable, like `xs.append`; call the method, or write a closure
