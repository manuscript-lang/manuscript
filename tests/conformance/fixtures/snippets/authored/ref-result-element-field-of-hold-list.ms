// conform: tags=ownership
// conform: phase=run
type Person {
	label String
}

fn first_label(hold items List[Person]) &String {
	return items[0].label
}

fn first_label_bound(hold items List[Person]) &String {
	p := items[0]
	return p.label
}

fn main() Void {
	people := [Person(label: "ada")]
	print(first_label(people))
	print(first_label_bound(people))
}
