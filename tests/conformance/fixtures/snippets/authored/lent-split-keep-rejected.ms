// conform: tags=strings,tier-core
// conform: phase=check
// conform: origin=lent-split
// `split`, `lines` and `chars` lend their receiver: keeping the result needs `.clone()`.
type Row:
	fields: List[String]

fn keep(line: String) Row:
	return Row(line.split(" "))

fn first_chars(text: String) List[String]:
	return text.chars()

fn kept_lines(text: String) List[String]:
	return text.lines()

fn mutate_while_used(text: String) Int:
	var line = text
	parts := line.split(" ")
	line = ""
	return parts.length()
