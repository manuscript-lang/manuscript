import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn is_digits(s: String, minlen: Int, maxlen: Int) Bool:
	n := s.length()
	if n < minlen or n > maxlen: return false
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

// returns empty list when invalid; otherwise flags indexed by value (size hi+1)
fn parse_field(s: String, lo: Int, hi: Int) List[Bool]:
	var flags = List[Bool]()
	for _i in 0..(hi + 1):
		flags.append(false)
	bad := List[Bool]()
	for item in s.split(","):
		parts := item.split("/")
		if parts.length() > 2: return bad
		base := parts.get(0, "")
		var step = 1
		has_step := parts.length() == 2
		if has_step:
			st := parts.get(1, "")
			if not is_digits(st, 1, 2): return bad
			step = num(st)
			if step < 1: return bad
		var a = lo
		var b = hi
		if base == "*":
			a = lo
			b = hi
		else:
			r := base.split("-")
			if r.length() == 1:
				if has_step: return bad
				x := r.get(0, "")
				if not is_digits(x, 1, 2): return bad
				a = num(x)
				b = a
			else if r.length() == 2:
				x := r.get(0, "")
				y := r.get(1, "")
				if not is_digits(x, 1, 2) or not is_digits(y, 1, 2): return bad
				a = num(x)
				b = num(y)
			else:
				return bad
			if a < lo or b > hi or a > b: return bad
		var v = a
		while v <= b:
			flags[v] = true
			v += step
	return flags

fn two(n: Int) String:
	return "{n}".pad_start(2, "0")

fn process(line: String, var out: List[String], ln: Int) Unit:
	toks := line.split(" ")
	if toks.length() != 7:
		out.append("line {ln}: error: bad line")
		return
	st := toks.get(0, "")
	var ok = st.length() == 16
	var y = 0
	var mo = 0
	var d = 0
	var hh = 0
	var mi = 0
	if ok:
		if st.slice(4, 5).get("") != "-" or st.slice(7, 8).get("") != "-" or st.slice(10, 11).get("") != "T" or st.slice(13, 14).get("") != ":":
			ok = false
	if ok:
		sy := st.slice(0, 4).get("")
		sm := st.slice(5, 7).get("")
		sd := st.slice(8, 10).get("")
		sh := st.slice(11, 13).get("")
		sn := st.slice(14, 16).get("")
		if not (is_digits(sy, 4, 4) and is_digits(sm, 2, 2) and is_digits(sd, 2, 2) and is_digits(sh, 2, 2) and is_digits(sn, 2, 2)):
			ok = false
		else:
			y = num(sy)
			mo = num(sm)
			d = num(sd)
			hh = num(sh)
			mi = num(sn)
			if y < 1970 or y > 2099 or mo < 1 or mo > 12 or hh > 23 or mi > 59 or d < 1 or d > dim(y, mo):
				ok = false
	if not ok:
		out.append("line {ln}: error: bad start")
		return
	cnt_s := toks.get(1, "")
	if not is_digits(cnt_s, 1, 2) or num(cnt_s) < 1 or num(cnt_s) > 20:
		out.append("line {ln}: error: bad count")
		return
	count := num(cnt_s)
	fm := parse_field(toks.get(2, ""), 0, 59)
	if fm.length() == 0:
		out.append("line {ln}: error: bad minute")
		return
	fh := parse_field(toks.get(3, ""), 0, 23)
	if fh.length() == 0:
		out.append("line {ln}: error: bad hour")
		return
	fd := parse_field(toks.get(4, ""), 1, 31)
	if fd.length() == 0:
		out.append("line {ln}: error: bad day-of-month")
		return
	fmo := parse_field(toks.get(5, ""), 1, 12)
	if fmo.length() == 0:
		out.append("line {ln}: error: bad month")
		return
	fw := parse_field(toks.get(6, ""), 0, 6)
	if fw.length() == 0:
		out.append("line {ln}: error: bad day-of-week")
		return
	// day of week of start
	var days = 0
	for yy in 1970..y:
		if leap(yy): days += 366
		else: days += 365
	for mm in 1..mo:
		days += dim(y, mm)
	days += d - 1
	var dow = (days + 4) % 7
	startmin := hh * 60 + mi
	var res = List[String]()
	for i in 0..3001:
		if fmo[mo] and fd[d] and fw[dow]:
			for h in 0..24:
				if not fh[h]: continue
				for m in 0..60:
					if not fm[m]: continue
					if i == 0 and h * 60 + m <= startmin: continue
					if res.length() < count:
						res.append("{y}-{two(mo)}-{two(d)} {two(h)}:{two(m)}")
		if res.length() >= count: break
		d += 1
		if d > dim(y, mo):
			d = 1
			mo += 1
			if mo > 12:
				mo = 1
				y += 1
		dow = (dow + 1) % 7
	if res.length() == 0:
		out.append("line {ln}: never")
		return
	out.append("line {ln}: {res.length()} runs")
	for r in res:
		out.append(r.clone())

fn main() Unit!:
	data := read_all(stdin(), none)?
	text := data.decode_utf8().get("")
	var out = List[String]()
	var ln = 0
	for line in text.split("\n"):
		ln += 1
		if line.trim_chars(" ") == "": continue
		process(line, var out, ln)
	if out.length() > 0:
		print(out.join("\n"))
