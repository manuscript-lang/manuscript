// conform: tags=ownership
// conform: phase=check
type Person {
	label String
}

fn borrowed(hold items List[Person]) &String {
	local := [Person(label: "x")]
	p := local[0]
	return p.label
}

fn direct(hold items List[Person]) &String {
	local := [Person(label: "x")]
	return local[0].label
}

fn main() Void {
	people := [Person(label: "ada")]
	print(borrowed(people))
	print(direct(people))
}
