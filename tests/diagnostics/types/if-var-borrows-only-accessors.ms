// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	var o List[String]? = ["a"]
	var n = 0
	if var l = o {
		l.append("q")
	}

	k := o
	if k != null {
		n += k.length()
	}
	return n
}
// expect-error: MS3000 6:12 `if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `o` is not one; read the payload by testing `if value != null { ... }`, then use `var copy = x.clone()` for an independent mutable copy, or write the changed value back
