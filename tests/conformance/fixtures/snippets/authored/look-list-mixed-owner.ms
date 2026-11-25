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
