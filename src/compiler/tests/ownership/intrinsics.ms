fn length_of(s: String) Int:
	return s.length()

fn literal_length() Int:
	return "hello".length()

fn after_use(s: String) String:
	n := s.length()
	t := s
	return t + n.to_string()

fn moved_then_read(s: String) Int:
	t := s
	return t.length() + s.length()

fn compare(a: String, b: String) Bool:
	return a.starts_with(b)
