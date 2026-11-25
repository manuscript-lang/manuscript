// conform: tags=ownership,records
// conform: phase=check
type Ref {
	name &String
	at Int
}

fn mix(hold names List[String]) List[Ref] {
	local := ["x"]
	var out = List[Ref]()
	out.append(Ref(names[0], 0))
	out.append(Ref(local[0], 1))
	return out
}

fn main() Void {
	names := ["a"]
	print(mix(names).length())
}
// expect-error: MS3000 8:1 a `&` result must be a part of a `hold` argument, but this body also puts a value it owns into the result; clone the part of the argument or keep only parts of the held argument
