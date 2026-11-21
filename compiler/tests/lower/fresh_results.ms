fn copy(s: String) String:
	return s.clone()

fn size(s: String) Int:
	return copy(s).length()

fn main() Int:
	return size("abc")
