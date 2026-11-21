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

fn use_parts(s: String) Int:
	parts := s.split(",")
	var n = 0
	for p in parts:
		n += p.length()
	return n

fn view_len(s: String) Int:
	head := s.view(0, 2)
	return head.length()

fn view_kept(s: String) String:
	head := s.view(0, 2)
	return head.clone()

fn mutate_while_borrowed(var s: String) Int:
	head := s.view(0, 2)
	s = "x"
	return head.length()

fn return_view(s: String) String:
	return s.view(0, 2)

fn pass_on(s: String) Int:
	return count(s.split(","))

fn count(parts: List[String]) Int:
	return parts.length()

fn compare_view(text: String) Bool:
	return text.view(4, 5) != "-"

fn interpolate(text: String) String:
	return f"{text.view(0, 4)}-{text.length()}"
