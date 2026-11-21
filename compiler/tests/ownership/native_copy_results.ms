fn order(a: String, b: String) Int:
	return a.compare(b)

fn first_or(values: List[String], fallback: String) Int:
	return values.length() + fallback.length()

fn present(name: String?) Bool:
	return name.is_some()
