import (
	stdin, stdout from "@std/io/io.ms",
	collect, lines from "@std/io/streams.ms",
)

fn is_leap(y: Int) Bool:
	return ((y % 4) == 0 and (y % 100) != 0) or (y % 400) == 0

fn dim(y: Int, m: Int) Int:
	if m == 2:
		if is_leap(y): return 29
		return 28

	if m == 4 or m == 6 or m == 9 or m == 11: return 30

	return 31

fn all_digits(s: String) Bool:
	for i in 0..s.length():
		if not "0123456789".contains(s.get(i)): return false
	return true

// Returns the value of a run of ASCII digits whose length is within [minlen, maxlen], or -1.
fn digits_value(s: String, minlen: Int, maxlen: Int) Int:
	n := s.length()
	if n < minlen or n > maxlen: return -1
	if not all_digits(s): return -1

	return s.parse_int().get(-1)

// Returns [year, month, day, hour, minute] or an empty list when START is invalid.
fn parse_start(s: String) List[Int]:
	var r = List[Int]()
	dt := s.split("T")
	if dt.length() != 2: return r

	dp := dt[0].split("-")
	tp := dt[1].split(":")
	if dp.length() != 3 or tp.length() != 2: return r
	if dp[0].length() != 4 or dp[1].length() != 2 or dp[2].length() != 2: return r
	if tp[0].length() != 2 or tp[1].length() != 2: return r

	y := digits_value(dp[0], 4, 4)
	mo := digits_value(dp[1], 2, 2)
	d := digits_value(dp[2], 2, 2)
	h := digits_value(tp[0], 2, 2)
	mi := digits_value(tp[1], 2, 2)
	if y < 1970 or y > 2099: return r
	if mo < 1 or mo > 12: return r
	if d < 1 or d > dim(y, mo): return r
	if h < 0 or h > 23 or mi < 0 or mi > 59: return r

	r.append(y)
	r.append(mo)
	r.append(d)
	r.append(h)
	r.append(mi)
	return r

// One cron item: *, */S, A, A-B, A-B/S. Marks matching values in set (index = value).
fn parse_item(item: String, lo: Int, hi: Int, var set: List[Bool]) Bool:
	sl := item.split("/")
	if sl.length() < 1 or sl.length() > 2: return false

	var step = 1

	if sl.length() == 2:
		step = digits_value(sl[1], 1, 2)
		if step < 1: return false

	base := sl[0]
	var a = lo
	var b = hi

	if base == "*":
		a = lo
		b = hi
	else:
		r := base.split("-")

		if r.length() == 1:
			if sl.length() == 2: return false

			a = digits_value(r[0], 1, 2)
			if a < lo or a > hi: return false

			b = a
		else if r.length() == 2:
			a = digits_value(r[0], 1, 2)
			b = digits_value(r[1], 1, 2)
			if a < lo or a > hi or b < lo or b > hi or a > b: return false
		else:
			return false

	var v = a

	while v <= b:
		set[v] = true
		v += step

	return true

// Returns a membership list indexed by value (size hi+1), or an empty list when invalid.
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
	var set = List[Bool]()
	for i in 0..hi + 1:
		set.append(false)
	for item in text.split(","):
		if not parse_item(item, lo, hi, var set): return List[Bool]()
	return set

fn pad2(n: Int) String:
	if n < 10: return "0{n}"
	return "{n}"

// Day of week with 0 = Sunday; 1970-01-01 was a Thursday.
fn day_of_week(y: Int, m: Int, d: Int) Int:
	var days = 0

	for yy in 1970..y:
		if is_leap(yy):
			days += 366
		else:
			days += 365

	for mm in 1..m:
		days += dim(y, mm)
	days += d - 1
	return (days + 4) % 7

fn search(
	start: List[Int],
	count: Int,
	mins: List[Bool],
	hours: List[Bool],
	doms: List[Bool],
	months: List[Bool],
	dows: List[Bool]
) List[String]:
	var res = List[String]()
	var y = start[0]
	var mo = start[1]
	var d = start[2]
	start_min := start[3] * 60 + start[4]
	var dow = day_of_week(y, mo, d)
	var day = 0

	while day <= 3000 and res.length() < count:
		if months[mo] and doms[d] and dows[dow]:
			var t = 0

			while t < 1440 and res.length() < count:
				h := t / 60
				mi := t % 60

				if hours[h] and mins[mi] and (day > 0 or t > start_min):
					ds := "{y}-{pad2(mo)}-{pad2(d)}"
					ts := "{pad2(h)}:{pad2(mi)}"
					res.append("{ds} {ts}")

				t += 1

		day += 1
		d += 1

		if d > dim(y, mo):
			d = 1
			mo += 1

			if mo > 12:
				mo = 1
				y += 1

		dow = (dow + 1) % 7

	return res

fn process(line: String, n: Int, var out: List[String]) Unit:
	if line.trim_chars(" ").is_empty(): return unit

	toks := line.split(" ")

	if toks.length() != 7:
		out.append("line {n}: error: bad line")
		return unit

	start := parse_start(toks[0])

	if start.is_empty():
		out.append("line {n}: error: bad start")
		return unit

	count := digits_value(toks[1], 1, 2)

	if count < 1 or count > 20:
		out.append("line {n}: error: bad count")
		return unit

	mins := parse_field(toks[2], 0, 59)

	if mins.is_empty():
		out.append("line {n}: error: bad minute")
		return unit

	hours := parse_field(toks[3], 0, 23)

	if hours.is_empty():
		out.append("line {n}: error: bad hour")
		return unit

	doms := parse_field(toks[4], 1, 31)

	if doms.is_empty():
		out.append("line {n}: error: bad day-of-month")
		return unit

	months := parse_field(toks[5], 1, 12)

	if months.is_empty():
		out.append("line {n}: error: bad month")
		return unit

	dows := parse_field(toks[6], 0, 6)

	if dows.is_empty():
		out.append("line {n}: error: bad day-of-week")
		return unit

	res := search(start, count, mins, hours, doms, months, dows)

	if res.is_empty():
		out.append("line {n}: never")
		return unit

	out.append("line {n}: {res.length()} runs")
	for r in res:
		out.append(r)

export fn main() Int:
	all := (stdin() | lines | collect(none)).get()
	var out = List[String]()
	var n = 0

	for line in all:
		n += 1
		process(line, n, var out)

	if not out.is_empty():
		text := out.join("\n")
		stdout().write("{text}\n").get()

	return 0
