import (
	stdin from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
	from_scalars from "@std/string.ms",
)

// A parsed record: the category text and the amount as little-endian cent digits.
type Record:
	category: String
	cents: List[Int]

fn is_digit(c: Int) Bool:
	return c >= 48 and c <= 57

// Parses "digits[.digits{1,2}]" into little-endian cent digits, or none.
fn amount_cents(cs: List[Int]) List[Int]?:
	var int_part = List[Int]()
	var frac = List[Int]()
	var seen_dot = false

	for c in cs:
		if c == 46:
			if seen_dot: return none

			seen_dot = true
		else if is_digit(c):
			if seen_dot: frac.append(c - 48)
			else: int_part.append(c - 48)
		else:
			return none

	if int_part.is_empty(): return none
	if seen_dot and (frac.is_empty() or frac.length() > 2): return none

	var out = List[Int]()

	if frac.length() == 2:
		out.append(frac[1])
		out.append(frac[0])
	else if frac.length() == 1:
		out.append(0)
		out.append(frac[0])
	else:
		out.append(0)
		out.append(0)

	var i = int_part.length() - 1

	while i >= 0:
		out.append(int_part[i])
		i -= 1

	return out

// Splits one line into category and amount; none if invalid.
fn parse_line(line: String) Record?:
	cs := line.scalar_values()
	n := cs.length()
	var cat = List[Int]()
	var amt_start = 0

	if n > 0 and cs[0] == 34:
		var close = -1

		for j in 1..n:
			if cs[j] == 34:
				close = j
				break

			cat.append(cs[j])

		if close < 0: return none
		if close + 1 >= n or cs[close + 1] != 44: return none

		amt_start = close + 2
	else:
		var comma = -1

		for j in 0..n:
			if cs[j] == 44:
				comma = j
				break

			cat.append(cs[j])

		if comma < 0: return none

		amt_start = comma + 1

	if cat.is_empty(): return none

	var amt = List[Int]()
	var k = amt_start

	while k < n:
		amt.append(cs[k])
		k += 1

	if cents := amount_cents(amt):
		if name := from_scalars(cat): return Record(category: name, cents: cents)
	return none

// Adds two little-endian digit lists.
fn add_cents(a: List[Int], b: List[Int]) List[Int]:
	var out = List[Int]()
	var carry = 0
	var i = 0

	while i < a.length() or i < b.length() or carry > 0:
		var s = carry
		if i < a.length(): s += a[i]
		if i < b.length(): s += b[i]
		out.append(s % 10)
		carry = s / 10
		i += 1

	return out

// Renders little-endian cent digits as "<int>.<two digits>".
fn render(cents: List[Int]) String:
	var d = cents.clone()
	while d.length() < 3: d.append(0)

	var text = ""
	var i = d.length() - 1

	while i >= 2:
		if text.is_empty() and d[i] == 0 and i > 2:
			i -= 1
			continue

		text = "{text}{d[i]}"
		i -= 1

	if text.is_empty(): text = "0"
	return "{text}.{d[1]}{d[0]}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn run() Int!:
	var names = List[String]()
	var totals = List[List[Int]]()
	var index = Map[String, Int]()
	var skipped = 0

	for line in lines(stdin()):
		if line.trim().is_empty(): continue

		if rec := parse_line(line):
			if idx := index.get(rec.category):
				totals[idx] = add_cents(totals[idx], rec.cents)
			else:
				index[rec.category.clone()] = names.length()
				names.append(rec.category)
				totals.append(rec.cents)
		else:
			skipped += 1

	var order = names.clone()
	order.sort()

	for name in order:
		idx := index.get_or(name, 0)
		print("{name}: {render(totals[idx])}")

	if skipped > 0:
		print("skipped: {skipped}")
	return ok(0)

export fn main() Int:
	if code := run(): return code
	return 1
