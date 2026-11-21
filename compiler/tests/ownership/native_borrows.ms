fn mutate_during(var s: String) Int:
	var n = 0

	for c in s.chars():
		s = "x"
		n += 1

	return n

fn clone_view(s: String) String:
	return s.view(1, 3).clone()

fn count_lines(text: String) Int:
	var n = 0
	for line in text.lines():
		n += line.length()
	return n

fn parts(text: String) Int:
	var n = 0
	for p in text.split(","):
		n += 1
	return n

fn keep(s: String) String:
	view := s.view(0, 1)
	return view.clone()
