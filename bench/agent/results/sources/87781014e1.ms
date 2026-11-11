import (
	stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

type Entry:
	cat: String
	cents: String

fn digit_value(c: String) Int:
	for d in 0..10:
		if digit_char(d) == c: return d
	return -1

fn digit_char(d: Int) String:
	return "0123456789".get(d)

fn is_digit(c: String) Bool:
	return digit_value(c) >= 0

// Joins scalars cs[from..to) into one string.
fn join_range(cs: List[String], from: Int, to: Int) String:
	var out = ""
	for i in from..to:
		out += cs[i]
	return out

// Validates `digits[.d[d]]` and returns the amount in cents as a digit string.
fn amount_cents(s: String) String?:
	cs := s.chars()
	n := cs.length()
	var i = 0
	var int_part = ""

	while i < n and is_digit(cs[i]):
		int_part += cs[i]
		i += 1

	if int_part.is_empty(): return none

	var frac = ""

	if i < n:
		if cs[i] != ".": return none

		i += 1

		while i < n and is_digit(cs[i]):
			frac += cs[i]
			i += 1

		if frac.length() < 1 or frac.length() > 2 or i != n: return none

		if frac.length() == 1:
			frac += "0"
	else:
		frac = "00"

	return int_part + frac

// Parses one non-blank line into a category and an amount in cents, or none if invalid.
fn parse_line(line: String) Entry?:
	cs := line.chars()
	n := cs.length()
	var cat = ""
	var amt_start = 0

	if n > 0 and cs[0] == "\"":
		var j = 1
		while j < n and cs[j] != "\"":
			j += 1
		if j >= n: return none
		if j + 1 >= n or cs[j + 1] != ",": return none

		cat = join_range(cs, 1, j)
		amt_start = j + 2
	else:
		var k = 0
		while k < n and cs[k] != ",":
			k += 1
		if k >= n: return none

		cat = join_range(cs, 0, k)
		amt_start = k + 1

	if cat.is_empty(): return none

	amount := join_range(cs, amt_start, n)
	if cents := amount_cents(amount): return Entry(cat: cat, cents: cents)

	return none

// Exact sum of two non-negative digit strings.
fn add_cents(a: String, b: String) String:
	x := a.chars()
	y := b.chars()
	var i = x.length() - 1
	var j = y.length() - 1
	var carry = 0
	var out = ""

	while i >= 0 or j >= 0 or carry > 0:
		var s = carry

		if i >= 0:
			s += digit_value(x[i])
			i -= 1

		if j >= 0:
			s += digit_value(y[j])
			j -= 1

		out = digit_char(s % 10) + out
		carry = s / 10

	return out

// Renders cents as "<int>.<two digits>".
fn format_cents(s: String) String:
	cs := ("000" + s).chars()
	n := cs.length()
	var k = 0
	while k < n - 3 and cs[k] == "0":
		k += 1
	return join_range(cs, k, n - 2) + "." + join_range(cs, n - 2, n)

export fn main() Int:
	var totals = Map[String, String]()
	var cats = List[String]()
	var skipped = 0
	var input = lines(stdin())

	while true:
		item := input.next().get()

		if line := item:
			if line.trim().is_empty(): continue

			if e := parse_line(line):
				if cur := totals.get(e.cat):
					sum := add_cents(cur, e.cents)
					totals[e.cat] = sum
				else:
					cats.append(e.cat.clone())
					totals[e.cat] = e.cents
			else:
				skipped += 1
		else:
			break

	var out = ""

	for cat in cats.sorted():
		total := format_cents(totals.get_or(cat, "0"))
		out += "{cat}: {total}\n"

	if skipped > 0:
		out += "skipped: {skipped}\n"
	stdout().write(out).get()
	return 0
