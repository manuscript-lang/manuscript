// A native read of an element the list keeps, handed to a position that would own it:
// an error, whichever way the receiving list was made.
fn from_literal(names: List[String]) List[String]:
	var out: List[String] = []
	out.append(names.get(0))
	return out

fn from_typed(names: List[String]) List[String]:
	var out = List[String]()
	out.append(names.get(0))
	return out

fn copied(names: List[String]) List[String]:
	var out = List[String]()
	out.append(names.get(0).clone())
	return out

fn main() Int:
	return (
		from_literal(["a"]).length()
		+ from_typed(["b"]).length()
		+ copied(["c"]).length()
	)
