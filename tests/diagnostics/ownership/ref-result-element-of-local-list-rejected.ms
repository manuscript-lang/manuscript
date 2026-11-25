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
// expect-error: MS3000 7:1 a `&` result must be a part of a `hold` argument, but this body returns a new value; remove the `&` or return a part of the held argument
// expect-error: MS3000 13:1 a `&` result must be a part of a `hold` argument, but this body returns a new value; remove the `&` or return a part of the held argument
