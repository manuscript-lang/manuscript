// conform: tags=ownership,records
// conform: phase=check
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
	var names = ["a", "b"]
	out := refs(names)
	names.append("c")
	print(out[0].name)
}
// expect-error: MS3000 19:5 cannot change `names` while `out` borrows it (binding of a part of it, at 18:5); finish using `out` before this, or give `out` its own value by ending its initializer with `.clone()`
