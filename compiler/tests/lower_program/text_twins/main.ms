fn a(s: String) String:
	return s.trim()

fn b(s: String) Int:
	t := s.trim()
	return t.length()

fn main() Void:
	print(" x ".trim())
	print(a(" y "))
	print(b(" z "))

	s := (" a " + "b ").trim().lower()
	print(s)
