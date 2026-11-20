// A call of a name that is nothing reports the name and does not check the arguments.
fn use_missing(n: Int) Int:
	return missing(n + 1.5)

fn use_typo(count: Int) Int:
	return coutn(count)
