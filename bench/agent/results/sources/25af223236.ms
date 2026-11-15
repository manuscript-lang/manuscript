import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_num(s: String, maxlen: Int) Bool:
	n := s.length()
	if n < 1 or n > maxlen: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn num(s: String) Int:
	return s.parse_int().get(0)

fn leap(y: Int) Bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

fn dim(y: Int, m: Int) Int:
	if m == 2:
		if leap(y): return 29
		return 28
	if m == 4 or m == 6 or m == 9 or m == 11: return 30
	return 31

fn mark(set: List[Bool], a: Int, b: Int, s: Int) Unit:
	return

// returns parsed set or empty list when invalid
fn parse_field(text: String, lo: Int, hi: Int) List[Bool]:
	var set = List[Bool]()
	for _i in 0..(hi + 1): set.append(false)
	bad := List[Bool]()
	for item in text.split(","):
		parts := item.split("/")
		if parts.length() > 2: return bad
		var step = 1
		if parts.length() == 2:
			if not is_num(parts.get(1, ""), 2): return bad
			step = num(parts.get(1, ""))
			if step < 1: return bad
		base := parts.get(0, "")
		var a = lo
		var b = hi
		if base == "*":
			a = lo
			b = hi
		else:
			r := base.split("-")
			if r.length() > 2: return bad
			if not is_num(r.get(0, ""), 2): return bad
			a = num(r.get(0, ""))
			if r.length() == 2:
				if not is_num(r.get(1, ""), 2): return bad
				b = num(r.get(1, ""))
			else:
				if parts.length() == 2: return bad
				b = a
			if a < lo or a > hi or b < lo or b > hi or a > b: return bad
		var v = a
		while v <= b:
			set[v] = true
			v += step
	return set

fn sub(cs: List[String], a: Int, b: Int) String:
	var out = ""
	for i in a..b: out = out + cs.get(i, "")
	return out

fn two(n: Int) String: "{n}".pad_start(2, "0")

fn process(line: String) List[String]:
	var out = List[String]()
	toks := line.split(" ")
	if toks.length() != 7:
		out.append("error: bad line")
		return out
	st := toks.get(0, "")
	cs := st.chars()
	var ok = cs.length() == 16
	var y = 0
	var mo = 0
	var d = 0
	var h = 0
	var mi = 0
	if ok:
		if cs.get(4, "") != "-" or cs.get(7, "") != "-" or cs.get(10, "") != "T" or cs.get(13, "") != ":": ok = false
	if ok:
		ys := sub(cs, 0, 4)
		ms := sub(cs, 5, 7)
		ds := sub(cs, 8, 10)
		hs := sub(cs, 11, 13)
		mns := sub(cs, 14, 16)
		if not (is_num(ys, 4) and is_num(ms, 2) and is_num(ds, 2) and is_num(hs, 2) and is_num(mns, 2)): ok = false
		else:
			y = num(ys)
			mo = num(ms)
			d = num(ds)
			h = num(hs)
			mi = num(mns)
			if y < 1970 or y > 2099 or mo < 1 or mo > 12 or d < 1 or h > 23 or mi > 59: ok = false
			else if d > dim(y, mo): ok = false
	if not ok:
		out.append("error: bad start")
		return out
	if not is_num(toks.get(1, ""), 2):
		out.append("error: bad count")
		return out
	count := num(toks.get(1, ""))
	if count < 1 or count > 20:
		out.append("error: bad count")
		return out
	fm := parse_field(toks.get(2, ""), 0, 59)
	if fm.length() == 0:
		out.append("error: bad minute")
		return out
	fh := parse_field(toks.get(3, ""), 0, 23)
	if fh.length() == 0:
		out.append("error: bad hour")
		return out
	fd := parse_field(toks.get(4, ""), 1, 31)
	if fd.length() == 0:
		out.append("error: bad day-of-month")
		return out
	fo := parse_field(toks.get(5, ""), 1, 12)
	if fo.length() == 0:
		out.append("error: bad month")
		return out
	fw := parse_field(toks.get(6, ""), 0, 6)
	if fw.length() == 0:
		out.append("error: bad day-of-week")
		return out
	// day of week of start
	var days = 0
	for yy in 1970..y: days += if leap(yy): 366 else: 365
	for mm in 1..mo: days += dim(y, mm)
	days += d - 1
	var dow = (days + 4) % 7
	var found = List[String]()
	for di in 0..3001:
		if found.length() >= count: break
		if fd[d] and fo[mo] and fw[dow]:
			for hh in 0..24:
				if not fh[hh]: continue
				for mm in 0..60:
					if not fm[mm]: continue
					if found.length() >= count: break
					if di == 0 and (hh < h or (hh == h and mm <= mi)): continue
					found.append("{y}-{two(mo)}-{two(d)} {two(hh)}:{two(mm)}")
		d += 1
		dow = (dow + 1) % 7
		if d > dim(y, mo):
			d = 1
			mo += 1
			if mo > 12:
				mo = 1
				y += 1
	if found.length() == 0:
		out.append("never")
		return out
	out.append("{found.length()} runs")
	for f in found: out.append(f.clone())
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var n = 0
	for line in lines(stdin()):
		n += 1
		if line.trim_chars(" ").length() == 0: continue
		res := process(line)
		first := res.get(0, "")
		if first.starts_with("error") or first == "never":
			print("line {n}: {first}")
		else:
			print("line {n}: {first}")
			for i in 1..res.length(): print(res.get(i, ""))
