fn greet(name: String?) String:
	if value := name:
		return "Hello, " + value
	return "Hello!"

fn keep(name: String?) String:
	if value := name:
		return value.clone()
	return "Anonymous"

fn first_or(items: List[String]?, fallback: String) String:
	if values := items:
		return fallback + values[0]
	return fallback

fn main() Int:
	_g := greet("Ada")
	_k := keep(none)
	_f := first_or(none, "x")
	return 0
