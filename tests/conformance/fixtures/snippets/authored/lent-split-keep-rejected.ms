// conform: tags=strings,tier-core
// conform: phase=check
// conform: origin=lent-split
// `split`, `lines` and `chars` lend their receiver: keeping the result needs `.clone()`.
type Row {
	fields List[String]
}

fn keep(line String) Row {
	return Row(line.split(" ").collect())
}

fn first_chars(hold text String) &List[String] {
	return text.chars()
}

fn kept_lines(text String) Row {
	return Row(text.lines().collect())
}

fn mutate_while_used(text String) Int {
	var line = text
	parts := line.split(" ").collect()
	line = ""
	return parts.length()
}
