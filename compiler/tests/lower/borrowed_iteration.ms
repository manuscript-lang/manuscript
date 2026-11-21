fn count_chars(text: String) Int:
	var n = 0
	for c in text.chars():
		n += c.length()
	return n

fn count_lines(text: String) Int:
	var n = 0
	for line in text.lines():
		n += line.length()
	return n

fn count_parts(text: String) Int:
	var n = 0
	for part in text.split(","):
		n += part.length() + 1
	return n

fn main() Void:
	print(count_chars("héllo"))
	print(count_lines("ab\ncde\nf"))
	print(count_parts("a,bc,,d"))
