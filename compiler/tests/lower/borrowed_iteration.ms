fn count_chars(extra: Int) Int:
	text := "héllo"
	var n = extra
	for c in text.chars():
		n += c.length()
	return n

fn count_lines(extra: Int) Int:
	text := "ab\ncde\nf"
	var n = extra
	for line in text.lines():
		n += line.length()
	return n

fn count_parts(extra: Int) Int:
	text := "a,bc,,d"
	var n = extra
	for part in text.split(","):
		n += part.length() + 1
	return n

fn view_length(from: Int) Int:
	text := "abcdefghijklmnopqrstuvwxyz"
	return text.view(from, 20).length()

fn clone_view(from: Int) String:
	text := "abcdefghijklmnopqrstuvwxyz"
	return text.view(from, 20).clone()

fn main() Void:
	print(count_chars(1))
	print(count_lines(1))
	print(count_parts(1))
	print(view_length(2))
	print(clone_view(3))
