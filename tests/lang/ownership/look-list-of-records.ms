// conform: tags=ownership,records
// conform: phase=run
type Ref {
	name &String
	at Int
}

fn refs(hold names List[String]) List[Ref] {
	var out = List[Ref]()
	for i in 0..names.length() {
		out.append(Ref(names[i], i))
	}
	return out
}

fn main() Void {
	names := ["abc", "def"]
	rs := refs(names)
	print(rs[0].name)
	print(rs[1].name)
	for r in rs {
		print(r.name)
	}
}
