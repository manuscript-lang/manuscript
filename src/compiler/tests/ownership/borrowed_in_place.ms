fn copied(names: List[String], at: Int) String:
	return names.get(at).clone()

fn length_of(names: List[String], at: Int) Int:
	return names.get(at).length()

fn same(names: List[String], other: List[String], at: Int) Bool:
	return names.get(at) == other.get(at)

fn kept(names: List[String], var out: List[String]) Void:
	out.append(names.get(0))
