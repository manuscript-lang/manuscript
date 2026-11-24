// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
	var o List[String]? = ["a"]
	var n = 0
	if var l = o:
		l.append("q")

	k := o
	if k != null:
		n += k.length()
	return n
