// conform: tags=strings,tier-core
// conform: phase=check
// conform: origin=lent-split
// `split`, `lines` and `chars` lend their receiver: keeping the result needs `.clone()`.
type Row {
	fields List[String]
}

fn keep(line String) Row {
	return Row(line.split(" "))
}

fn first_chars(hold text String) &List[String] {
	return text.chars()
}

fn kept_lines(hold text String) &List[String] {
	return text.lines()
}

fn mutate_while_used(text String) Int {
	var line = text
	parts := line.split(" ")
	line = ""
	return parts.length()
}
// expect-error: MS3000 10:21 `split` borrows `line`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 14:17 `chars` borrows `text`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 18:17 `lines` borrows `text`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 24:5 cannot reassign `line` while `parts` borrows it (binding of a part of it, at 23:5); finish using `parts` before this, or give `parts` its own value by ending its initializer with `.clone()`
