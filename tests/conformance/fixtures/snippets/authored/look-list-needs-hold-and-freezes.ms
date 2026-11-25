// conform: tags=ownership,records
// conform: phase=check
type Ref {
	name &String
	at Int
}

fn refs(names List[String]) List[Ref] {
	var out = List[Ref]()
	for i in 0..names.length() {
		out.append(Ref(names[i], i))
	}
	return out
}

fn bad() List[Ref] {
	local := ["x"]
	var out = List[Ref]()
	out.append(Ref(local[0], 0))
	return out
}

fn main() Void {
	var names = ["a", "b"]
	out := refs(names)
	names.append("c")
	print(out[0].name)
}
// expect-error: MS3000 8:1 a `&` result points into an argument; mark that argument `hold`, or return an owned value
// expect-error: MS3000 16:1 a `&` result points into an argument; mark that argument `hold`, or return an owned value
